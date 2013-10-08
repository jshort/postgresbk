
require_relative "backup_quiesce_interface"
require 'pg'
require 'fileutils'

class ConnectionsStillPendingException < Exception
end

class NoBackupsAvailableException < Exception
end

class Postgresbk
  include BackupQuiesceInterface

  def initialize options
    @options = options
    
    conn_hash = { 
                 "dbname" => "postgres",
                 "user" => @options[:user], 
                 "port" => @options[:port]
                }

    # The following hack is to allow a connection to the template db in the event that the db being quiesced is the postgres db.
    #   It might just be better to always connect to template1 since it should always exist
    conn_hash["dbname"] = "template1" if @options[:database] == conn_hash["dbname"]

    begin
      @conn = PG::Connection.new conn_hash 
    rescue PG::ConnectionBad => e
      tries ||= 1
      # If the database is already quiesced, connect using one of the default/system databases to unquiesce.
      #   I don't like the hardcoded "template1" below because you must connect to a database that is NOT the one
      #   you are unquiescing since you can't connect to said database after it has been quiesced. 
      if e.message.index("is not currently accepting connections") && (tries -= 1).zero?
        conn_hash["dbname"] = "template1"
        retry
      end

      raise PG::ConnectionBad.new "Connection failed to database: #{@options[:database]} as user: #{@options[:user]} on port: #{@options[:port]}"
    end
  end

  def quiesce 
    retry_int = 5
    begin
      # Prevent any further connections
      set_dataallowcon_to false

      # Now some retry logic that checks for connections needs to be made and only return when not only the
      #   database is locked down, but that there are no active connections.  Unfortuantely there has be a point 
      #   which this method returns in the event there are long lived connections.  Will kill leftover connections 
      #   after the  retry time frame
      (1..@options[:waittime]/retry_int).each do |n|
        res = @conn.exec("SELECT count(*) FROM pg_catalog.pg_stat_activity WHERE datname='#{@options[:database]}'")
        if res[0]['count'] == '0'
          return
        else
          sleep retry_int
        end
      end

      # At this point there are still active connections on the database so depending on the user input, you fail
      #   or if the kill flag was given, then you execute a query to kill those connections
      if @options[:kill_at_timeout]
        @conn.exec("SELECT pg_catalog.pg_terminate_backend(pid) FROM pg_catalog.pg_stat_activity WHERE datname='#{@options[:database]}'")
      else
        # Unquiesce the database due to the failure and raise an exception and return non-zero to the client
        set_dataallowcon_to true
        raise ConnectionsStillPendingException.new "There are still connections to #{@options[:database]} and no kill flag was passed"
      end
    rescue Exception => e
      raise e
    end
  end

  def unquiesce 
    # Simply execute the query to set datallowconn=true for the database
    begin
      set_dataallowcon_to true
    rescue Exception => e
      raise e
    end
  end

  # Unfortuantely pg_dump does not work if datallowcon=false (ie quiesced) so logic needs to be implemented to check if
  #   the database can receive connections and if not, turn it back on just before running the pg_dump.  At the end of the 
  #   method, it should put the datallowcon back to the state it was in originally
  def backup 
    begin
      check_if_db_exists
      is_allowed = @conn.exec("select datallowconn from pg_catalog.pg_database where datname='#{@options[:database]}'")[0]['datallowconn']
      if is_allowed == 'f'
        # unquiece temporarily
        set_dataallowcon_to true
      end

      # Check to see if the directory for backups exists and if not, create it with parents
      unless File.exist?(@options[:bkdir])
        FileUtils.mkdir_p @options[:bkdir]
      end
      filename = "postgresbk_#{@options[:database]}_#{Time.new.strftime("%m%d%y%H%M%S")}.dump"

      # The below system call assumes you have passwordless access as the user passed into the executable tool
      #   either due to ~/.pgpass or pg_hba.conf has your user as a 'trust' auth method
      `pg_dump -U #{@options[:user]} #{@options[:database]} -F c -f #{@options[:bkdir]}/#{filename}`

    rescue Exception => e
      raise e
    ensure
      if is_allowed == 'f'
        # re quiesce 
        set_dataallowcon_to false
      end
    end
  end

  # Similarly to pg_dump, pg_restore does not work if datallowcon=false (ie quiesced) so logic needs to be implemented to check if
  #   the database can receive connections and if not, turn it back on just before running the pg_restore.  At the end of the 
  #   method, it should put the datallowcon back to the state it was in originally
  def restore 
    # pg_restore -c -U postgres -d dataslam -1 /tmp/out.dump
    begin
      check_if_db_exists
      is_allowed = @conn.exec("select datallowconn from pg_catalog.pg_database where datname='#{@options[:database]}'")[0]['datallowconn']
      if is_allowed == 'f'
        # unquiece temporarily
        set_dataallowcon_to true
      end

      fn = get_latest_backup_fn

      if fn == ""
        raise NoBackupsAvailableException.new "There are no backups available at the specified location or in the default location (/tmp/postgresbk)"
      end

      # The below system call assumes you have passwordless access as the user passed into the executable tool
      #   either due to ~/.pgpass or pg_hba.conf has your user as a 'trust' auth method
      `pg_restore -c -U #{@options[:user]} -d #{@options[:database]} -1 #{@options[:bkdir]}/#{fn}`

    rescue Exception => e
      raise e
    ensure
      if is_allowed == 'f'
        # re quiesce 
        set_dataallowcon_to false
      end
    end
  end

  # Below are some private helper methods
  private

  def get_latest_backup_fn
    largest = 0
    newest_fn = ""
    Dir.foreach(@options[:bkdir]) do |f|
      if f.index(@options[:database])
        first_ind = f.rindex('_')
        last_ind  = f.rindex('.')
        current = f[first_ind+1..last_ind-1].to_i
        largest = current and newest_fn = f if current > largest
      end
    end
    newest_fn

  end

  def set_dataallowcon_to boolean
    check_if_db_exists
    @conn.exec("UPDATE pg_catalog.pg_database SET datallowconn=#{boolean.to_s} WHERE datname='#{@options[:database]}'")
  end

  def check_if_db_exists
    count = @conn.exec("SELECT count(*) FROM pg_catalog.pg_database WHERE datname='#{@options[:database]}'")[0]['count']
    if count == '0'
      raise PG::ConnectionBad.new "FATAL:  database \"#{@options[:database]}\" does not exist"
    end
  end
end