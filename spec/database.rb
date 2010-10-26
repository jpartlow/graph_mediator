require 'rubygems'

gem 'activerecord', '>=2.3.5'
require 'active_record'

ActiveRecord::Base.establish_connection({'adapter' => 'sqlite3', 'database' => ':memory:'})
ActiveRecord::Base.logger = Logger.new("#{File.dirname(__FILE__)}/active_record.log")

def create_schema(&block)
  connection = ActiveRecord::Base.connection
  yield connection if block_given?
end
