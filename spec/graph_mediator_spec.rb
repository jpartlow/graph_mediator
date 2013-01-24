require File.expand_path(File.join(File.dirname(__FILE__), 'spec_helper'))

module GraphMediatorSpec # name space so these helper classes don't collide with another running spec

class Foo < ActiveRecord::Base
  include GraphMediator
end

class UntimestampedThing < ActiveRecord::Base
  include GraphMediator
end

class UnlockedThing < ActiveRecord::Base
  include GraphMediator
end

class PlainThing < ActiveRecord::Base
  include GraphMediator
end

describe "GraphMediator" do

  before(:all) do
    create_schema do |conn|
      conn.create_table(:foos, :force => true) do |t|
        t.string :foo
        t.integer :lock_version, :default => 0
        t.timestamps
      end
    
      conn.create_table(:bars, :force => true) do |t|
        t.string :bar
        t.integer :lock_version, :default => 0
        t.timestamps
      end
      
      conn.create_table(:untimestamped_things, :force => true) do |t|
        t.string :name
        t.integer :lock_version, :default => 0
      end
    
      conn.create_table(:unlocked_things, :force => true) do |t|
        t.string :name
        t.timestamps
      end
    
      conn.create_table(:plain_things, :force => true) do |t|
        t.string :name
      end
    end
  end

  it "should provide a module attribute accessor for turning mediation on or off" do
    GraphMediator::Configuration.enable_mediation.should == true
    GraphMediator::Configuration.enable_mediation = false
    GraphMediator::Configuration.enable_mediation.should == false
  end

  it "should be able to disable and enable mediation globally"

  it "should insert a MediatorProxy class when included" do
    Foo::MediatorProxy.should include(GraphMediator::Proxy)
    Foo.should include(Foo::MediatorProxy)
  end

  it "should provide the mediate class macro" do
    Foo.should respond_to(:mediate) 
  end

  it "should provide the mediate_reconciles class macro" do
    Foo.should respond_to(:mediate_reconciles)
  end

  it "should provide the mediate_caches class macro" do
    Foo.should respond_to(:mediate_caches)
  end

  context "testing logger" do
    class LoggerTest < ActiveRecord::Base
      include GraphMediator
      def log_me
        logger.debug('hi')
      end
      def log_me_graph_mediator
        m_info('gm')
      end
    end
    
    before(:all) do
      create_schema do |conn|
        conn.create_table(:logger_tests, :force => true) do |t|
          t.string :name
        end
      end
    end

    before(:each) do
      @lt = LoggerTest.create!
    end

    it "should have the base logger" do
      LoggerTest.logger.should_not be_nil
      LoggerTest.logger.should == ActiveRecord::Base.logger
    end

    it "should have a MediatorProxy logger" do
      LoggerTest::MediatorProxy._graph_mediator_logger.should_not be_nil
      LoggerTest::MediatorProxy._graph_mediator_logger.should == LoggerTest.logger
    end

    it "should have the base logger for instances" do
      @lt.logger.should_not be_nil
      @lt.logger.should == ActiveRecord::Base.logger
    end

    it "should have the mediator logger for instances" do
      @lt.logger.should_not be_nil
      @lt.logger.should == ActiveRecord::Base.logger
    end

    it "should be possible to override base logger" do
      begin
        mock_logger = mock("logger")
        mock_logger.should_receive(:debug).once.with('hi')
        current_logger = ActiveRecord::Base.logger
        LoggerTest.logger = mock_logger
        @lt.log_me
      ensure
        LoggerTest.logger = current_logger
      end
    end
    
    it "should be possible to override graph logger" do
      mock_logger = mock("logger")
      mock_logger.should_receive(:info).once.with('gm')
      LoggerTest::MediatorProxy._graph_mediator_logger = mock_logger
      @lt.log_me_graph_mediator
    end
  end

  context "with a fresh class" do
  
    def load_bar
      c = Class.new(ActiveRecord::Base)
      Object.const_set(:Bar, c)
      c.__send__(:include, GraphMediator)
    end

    before(:each) do
      load_bar
    end

    after(:each) do
      Object.__send__(:remove_const, :Bar)
    end

    it "should get the when_reconciling option" do
#      Bar.__graph_mediator_reconciliation_callbacks.should == []
      Bar.mediate :when_reconciling => :foo
      Bar.mediate_reconciles_callback_chain.should == [:foo]
#      Bar.__graph_mediator_reconciliation_callbacks.size.should == 1
#      Bar.__graph_mediator_reconciliation_callbacks.first.should be_kind_of(Proc)
    end
 
    it "should collect methods through mediate_reconciles" do
#      Bar.__graph_mediator_reconciliation_callbacks.should == []
      Bar.mediate :when_reconciling => [:foo, :bar]
      Bar.mediate_reconciles :baz do
        biscuit
      end
      Bar.mediate_reconciles_callback_chain.should include(:foo, :bar, :baz)
      Bar.mediate_reconciles_callback_chain.should have(4).elements
#      Bar.__graph_mediator_reconciliation_callbacks.should have3
#      Bar.__graph_mediator_reconciliation_callbacks.each { |e| e.should be_kind_of(Proc) }
    end
 
    it "should get the when_cacheing option" do
      Bar.mediate :when_cacheing => :foo
      Bar.mediate_caches_callback_chain.should == [:foo]
    end
  
    it "should collect methods through mediate_caches" do
      Bar.mediate :when_cacheing => [:foo, :bar]
      Bar.mediate_caches :baz do
        biscuit
      end
      Bar.mediate_caches_callback_chain.should include(:foo, :bar, :baz)
      Bar.mediate_caches_callback_chain.should have(4).elements
    end
 
    it "should get the dependencies option" do
      begin
        class ::Child < ActiveRecord::Base; end
        Bar.mediate :dependencies => Child
      ensure
        Object.__send__(:remove_const, :Child) 
      end
    end

  end

  context "with a defined mediation" do 

    before(:each) do
      load_traceable_callback_tester
      @t = Traceable.new(:name => :gizmo)
    end

    after(:each) do
      Object.__send__(:remove_const, :Traceable)
    end

    it "should be able to disable and enable mediation for the whole class" do
      Traceable.disable_all_mediation!
      @t.save
      @t.save!
      @traceables_callbacks.should == []
      Traceable.enable_all_mediation!
      @t.save
      @t.save!
      @traceables_callbacks.should == [:before, :reconcile, :cache, :before, :reconcile, :cache,]
    end

    it "should disable and enable mediation for an instance" do
      @t.disable_mediation!
      @t.save
      @t.save!
      @traceables_callbacks.should == []
      @t.enable_mediation!
      @t.save
      @t.save!
      @traceables_callbacks.should == [:before, :reconcile, :cache, :before, :reconcile, :cache,]
    end

    it "should have save_without_mediation convenience methods" do
      @t.save_without_mediation
      @t.save_without_mediation!
      @traceables_callbacks.should == []
    end

    it "should have update_attributes_without_mediation convenience methods" do
      @t.update_attributes_without_mediation(:name => :foo)
      @t.update_attributes_without_mediation!(:name => :bar)
      @traceables_callbacks.should == []
    end

    it "should handle saving a new record" do
      n = Traceable.new(:name => 'new')
      n.save!
      @traceables_callbacks.should == [:before, :reconcile, :cache,]
    end

    it "should handle updating an existing record" do
      e = Traceable.create!(:name => 'exists')
      @traceables_callbacks.clear
      e.save!
      @traceables_callbacks.should == [:before, :reconcile, :cache,]
    end

    it "should nest mediated transactions" do
      Traceable.class_eval do
        after_create do |instance|
          instance.mediated_transaction do
            instance.callbacks << :nested_create!
          end
        end
        after_save do |instance|
          instance.mediated_transaction do
            instance.callbacks << :nested_save!
          end
        end
      end
      nested = Traceable.create!(:name => :nested!)
      @traceables_callbacks.should == [:before, :nested_create!, :nested_save!, :reconcile, :cache, :nested_save!]
      # The final nested save is the touch and lock_version bump
    end

    # can't nest before_create.  The second mediated_transaction will occur
    # before instance has an id, so we have no way to look up a mediator.
    # XXX actually, it appears you can?
    it "cannot nest mediated transactions before_create if versioning" do
      Traceable.class_eval do
        before_create do |instance|
          instance.mediated_transaction do
            instance.callbacks << :nested_before_create!
          end
        end
      end
      #lambda { nested = Traceable.create!(:name => :nested!) }.should raise_error(GraphMediator::MediatorException)
      nested = Traceable.create!(:name => :nested!)
      @traceables_callbacks.should == [:before, :nested_before_create!, :reconcile, :cache]
    end

    it "should cull mediator after an exception in mediation" do
      lambda { @t.mediated_transaction do
        raise
      end }.should raise_error(RuntimeError)
      @t.__send__(:current_mediator).should be_nil
    end

    it "should override save" do
      @t.save
      @traceables_callbacks.should == [:before, :reconcile, :cache,] 
      @t.new_record?.should be_false
    end

    it "should override save bang" do
      @t.save!
      @traceables_callbacks.should == [:before, :reconcile, :cache,] 
      @t.new_record?.should be_false
    end

    it "should allow me to override save locally" do
      Traceable.class_eval do
        def save
          callbacks << '...saving...'
          super
        end
      end
      @t.save
      @traceables_callbacks.should == ['...saving...', :before, :reconcile, :cache,] 
      @t.new_record?.should be_false
    end

    it "should allow me to decorate save_with_mediation" do
      Traceable.class_eval do
        alias_method :save_without_transactions_with_mediation_without_logging, :save_without_transactions_with_mediation
        def save_without_transactions_with_mediation(*args)
          callbacks << '...saving...'
          save_without_transactions_with_mediation_without_logging(*args)
        end
      end
      @t.save
      @traceables_callbacks.should == ['...saving...', :before, :reconcile, :cache,] 
      @t.new_record?.should be_false
    end

    it "should allow me to decorate save_without_mediation" do
      Traceable.class_eval do
        alias_method :save_without_transactions_without_mediation_without_logging, :save_without_transactions_without_mediation
        def save_without_transactions_without_mediation(*args)
          callbacks << '...saving...'
          save_without_transactions_without_mediation_without_logging(*args)
        end
      end
      @t.save
      @traceables_callbacks.should == [:before, '...saving...', :reconcile, :cache,] 
      @t.new_record?.should be_false
    end

  end

  context "with an instance" do

    before(:each) do
      @f = Foo.new
    end

    it "cannot update lock_version without timestamps" do
      t = UntimestampedThing.create!(:name => 'one')
      t.lock_version.should == 0
      t.touch
      t.lock_version.should == 0
      t.mediated_transaction {}
      t.lock_version.should == 0
    end

    it "should update lock_version on touch if instance has timestamps" do
      @f.save!
      @f.lock_version.should == 1
      @f.touch
      @f.lock_version.should == 2
    end

    context "with mediation disabled" do
      before(:each) do
        Foo.disable_all_mediation!
      end

      after(:each) do
        Foo.enable_all_mediation!
      end

      it "should update lock_version normally if mediation is off" do
        @f.save!
        @f.lock_version.should == 0
        @f.update_attributes(:foo => 'foo')
        @f.lock_version.should == 1
      end
    end

    it "should get a mediator" do
      begin 
        mediator = @f.__send__(:_get_mediator)
        mediator.should be_kind_of(GraphMediator::Mediator)
        mediator.mediated_instance.should == @f 
      ensure
        @f.__send__(:mediators_for_new_records).clear
      end
    end

    it "should get the same mediator for a new record if called from the same instance" do
      begin
        @f.new_record?.should be_true
        mediator1 = @f.__send__(:_get_mediator)
        mediator2 = @f.__send__(:_get_mediator)
        mediator1.should equal(mediator2)
      ensure
        @f.__send__(:mediators_for_new_records).clear
      end
    end

    it "should get the same mediator for a saved record" do
      begin
        @f.save_without_mediation
        @f.new_record?.should be_false
        mediator1 = @f.__send__(:_get_mediator)
        mediator2 = @f.__send__(:_get_mediator)
        mediator1.should equal(mediator2)
      ensure
        @f.__send__(:mediators).clear
      end
    end

    # @f.create -> calls save, which engages mediation on a new record which has no id.
    # During the creation process (after_create) @f will have an id.
    # Other callbacks may create dependent objects, which will attempt to mediate, or
    # other mediated methods, and these should receive the original mediator if we have
    # reached after_create stage.
    it "should get the same mediator for a new record that is saved during mediation" do
      begin
        @f.new_record?.should be_true
        mediator1 = @f.__send__(:_get_mediator)
        @f.mediated_transaction do
          @f.save
          mediator2 = @f.__send__(:_get_mediator)
          mediator1.should equal(mediator2)
        end
      ensure
        @f.__send__(:mediators_for_new_records).clear
        @f.__send__(:mediators).clear
      end
    end

    it "should indicate if currently mediating for a new instance" do
      @f.currently_mediating?.should be_false
      @f.mediated_transaction do
        @f.currently_mediating?.should be_true
      end
    end

    it "should indicate if currently mediating for an existing instance" do
      @f.save!
      @f.currently_mediating?.should be_false
      @f.mediated_transaction do
        @f.currently_mediating?.should be_true
      end
    end

    it "should expose the current phase of mediation" do
      @f.current_mediation_phase.should be_nil
      @f.mediated_transaction do
        @f.current_mediation_phase.should == :mediating
      end
      @f.save!
      @f.current_mediation_phase.should be_nil
      @f.mediated_transaction do
        @f.current_mediation_phase.should == :mediating
      end
    end

    it "should expose mediated_changes" do
      @f.mediated_changes.should be_nil
      @f.mediated_transaction do
        @f.mediated_changes.should == {}
      end
    end

# TODO - may need to move this up to the class

    it "should generate a unique mediator_hash_key for each MediatorProxy" do
      @f.class.mediator_hash_key.should == 'GRAPH_MEDIATOR_GRAPH_MEDIATOR_SPEC_FOO_HASH_KEY'
    end

    it "should generate a unique mediator_new_array_key for each MediatorProxy" do
      @f.class.mediator_new_array_key.should == 'GRAPH_MEDIATOR_GRAPH_MEDIATOR_SPEC_FOO_NEW_ARRAY_KEY'
    end

    it "should generate a unique mediator_being_destroyed_array_key for each MediatorProxy" do
      @f.class.mediator_being_destroyed_array_key.should == 'GRAPH_MEDIATOR_GRAPH_MEDIATOR_SPEC_FOO_BEING_DESTROYED_ARRAY_KEY'
    end

    it "should access an array of mediators for new records" do
      @f.__send__(:mediators_for_new_records).should == []
    end

    it "should access a hash of mediators" do
      @f.__send__(:mediators).should == {}
    end

    it "should access an array of ids for instances being destroyed" do
      @f.__send__(:instances_being_destroyed).should == []
    end
  end
end

end
