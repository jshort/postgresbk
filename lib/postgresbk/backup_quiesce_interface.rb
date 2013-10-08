
# This is a ruby module to act as the base interface for a generic framework for quiescing, unquiescing, 
#   backing up and restoring a relational database such as PostgreSQL or MySQL, etc.
module BackupQuiesceInterface
  # This method is to quiesce a database which means stop future connections and wait for existing
  #   connections to end to allow for a cleaner backup (though not mandatory for using backup).
  #   This method is idempotent and will have no effect if run against an already quiesced database.
  def quiesce 
    raise NotImplementedError.new
  end

  # This method is unquiece a datbase which means open said database back up to allow connections.  This 
  #   method is also idempotent and will not affect database usage if called on an already functioning 
  #   database
  def unquiesce 
    raise NotImplementedError.new
  end

  # This method is to create a backup of the database in question and store it in the specified or default
  #   backup location.  It is best to call this method when the database is already quiesced, though that is 
  #   not required nor enforced though you must proceed with caution
  def backup 
    raise NotImplementedError.new
  end

  # This method is to restore the last (chronologically) created backup to the specified database.  It is 
  #   best to call this method when the database is already quiesced, though that is not required nor enforced 
  #   though you must proceed with caution
  def restore 
    raise NotImplementedError.new
  end
end