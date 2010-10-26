$LOAD_PATH.unshift(File.dirname(__FILE__))
$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))
require 'graph_mediator'
require 'spec'
require 'spec/autorun'
require 'pp'

require 'database'
require 'factory'

Spec::Runner.configure do |config|
  
  # Ensures each listed class is cleared from the objectspace and reloaded.
  # RSpec does not reload classes between tests, so if you're testing class
  # variables/class instance variables, they accumulate state between tests.
  # Also a problem if you mock a class method.
  def reload_classes(*classes) 
    classes.each do |constant|
      md = constant.to_s.match(/^(.*?)(?:::)?([^:]+)$/)
      klass = (matched_both = md.captures.size == 2) ? md[2] : md[1]
      namespace = md[1] if matched_both
      (namespace.try(:constantize) || Object).send(:remove_const, klass.to_s.to_sym)
    end
    classes.each do |constant|
      load "#{constant.to_s.underscore}.rb"
    end
  end

end
