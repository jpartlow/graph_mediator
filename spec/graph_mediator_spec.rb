require File.expand_path(File.join(File.dirname(__FILE__), 'spec_helper'))

create_schema do |conn|
  conn.create_table(:foos, :force => true) do |t|
    t.string :foo
  end

  conn.create_table(:bars, :force => true) do |t|
    t.string :bar
  end
  
  conn.create_table(:things, :force => true) do |t|
    t.string :name
  end
end

class Foo < ActiveRecord::Base
  include GraphMediator
end

describe "GraphMediator" do

  it "should provide a module attribute accessor for turning mediation on or off" do
    GraphMediator.enable_mediation.should == true
    GraphMediator.enable_mediation = false
    GraphMediator.enable_mediation.should == false
  end

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
 
    it "should get the when_bumping option" do
      Bar.mediate :when_bumping => :foo
      Bar.mediate_bumps_callback_chain.should == [:foo]
    end
  
    it "should collect methods through mediate_bumps" do
      Bar.mediate_bumps :foo
      Bar.mediate_bumps_callback_chain.should == [:foo] 
    end

    it "should get the bumps option" do
      Bar.__graph_mediator_version_column.should be_nil
      Bar.mediate :bumps => :foo
      Bar.__graph_mediator_version_column.should == :foo
    end
 
    it "should ignore bumps if mediate_bumps callback is set"
 
    it "should get the dependencies option"

  end

  context "with a defined mediation" do 

    def load_thing
      c = Class.new(ActiveRecord::Base)
      Object.const_set(:Thing, c)
      c.class_eval do
        include GraphMediator
        attr_accessor :callbacks
         
        mediate :when_reconciling => :reconcile, :when_cacheing => :cache, :when_bumping => :bump
        before_mediation :before
     
        def initialize(*attributes)
          self.callbacks = []
          super
        end 
        def before; callbacks << :before; end
        def reconcile; callbacks << :reconcile; end
        def cache; callbacks << :cache; end
        def bump; callbacks << :bump; end
      end
    end

    before(:each) do
      load_thing
      @t = Thing.new(:name => :gizmo)
    end

    after(:each) do
      Object.__send__(:remove_const, :Thing)
    end

    it "should override save" do
      @t.save
      @t.callbacks.should == [:before, :reconcile, :cache, :bump] 
      @t.new_record?.should be_false
    end

    it "should override save!" do
      @t.save!
      @t.callbacks.should == [:before, :reconcile, :cache, :bump] 
      @t.new_record?.should be_false
    end

    it "should allow me to override save locally" do
      Thing.class_eval do
        def save
          callbacks << '...saving...'
          super
        end
      end
      @t.save
      @t.callbacks.should == ['...saving...', :before, :reconcile, :cache, :bump] 
      @t.new_record?.should be_false
    end

    it "should allow me to decorate save_with_mediation" do
      Thing.class_eval do
        alias_method :save_without_transactions_with_mediation_without_logging, :save_without_transactions_with_mediation
        def save_without_transactions_with_mediation(*args)
          callbacks << '...saving...'
          save_without_transactions_with_mediation_without_logging(*args)
        end
      end
      @t.save
      @t.callbacks.should == ['...saving...', :before, :reconcile, :cache, :bump] 
      @t.new_record?.should be_false
    end

    it "should allow me to decorate save_without_mediation" do
      Thing.class_eval do
        alias_method :save_without_transactions_without_mediation_without_logging, :save_without_transactions_without_mediation
        def save_without_transactions_without_mediation(*args)
          callbacks << '...saving...'
          save_without_transactions_without_mediation_without_logging(*args)
        end
      end
      @t.save
      @t.callbacks.should == [:before, '...saving...', :reconcile, :cache, :bump] 
      @t.new_record?.should be_false
    end

  end

  context "with an instance" do

    before(:each) do
      @f = Foo.new
    end

# TODO - may need to move this up to the class

    it "should generate a unique mediator_hash_key for each MediatorProxy" do
      @f.__send__(:mediator_hash_key).should == 'GRAPH_MEDIATOR_FOO_HASH_KEY'
    end

    it "should access a hash of mediators" do
      @f.__send__(:mediators).should == {}
    end

    it "should provide an a before_mediation callback" do
      @f.should respond_to(:before_mediation)
    end

    it "should provide an a after_mediation callback" do
      @f.should respond_to(:after_mediation)
    end

  end
end
