$LOAD_PATH.unshift(File.dirname(__FILE__))
$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))
require 'graph_mediator'
require 'spec'
require 'spec/autorun'
require 'pp'

require 'database'
require 'factory'

class TestLogger
  [:debug, :info, :warn, :error].each do |m|
    define_method(m) { |message| puts "#{m.to_s.upcase}: #{message}" }
  end
end

Spec::Runner.configure do |config|

  def require_reservations
    require 'reservations/schema'
    require 'reservations/reservation'
  end
  
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

  # Provides a class Traceable which records calls in @traceables_callbacks
  def load_traceable_callback_tester
    create_schema do |conn|
      conn.create_table(:traceables, :force => true) do |t|
        t.string :name
        t.integer :lock_version, :default => 0
        t.timestamps
      end
    end

    # make sure we record all callback calls regardless of which instance we're in.
    @traceables_callbacks = callbacks_ref = []
    c = Class.new(ActiveRecord::Base)
    Object.const_set(:Traceable, c)
    c.class_eval do
      include GraphMediator
       
      mediate :when_reconciling => :reconcile, :when_cacheing => :cache
      before_mediation :before
   
      def before; callbacks << :before; end
      def reconcile; callbacks << :reconcile; end
      def cache; callbacks << :cache; end
      define_method(:callbacks) { callbacks_ref }
    end
  end

end
