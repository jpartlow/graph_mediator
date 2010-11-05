require File.expand_path(File.join(File.dirname(__FILE__), '..', 'spec_helper'))

describe "Nesting of mediated_transactions" do

  before(:all) do
    #@old_logger = GraphMediator::Configuration.logger
    #GraphMediator::Configuration.logger = TestLogger.new
    @old_log_level = GraphMediator::Configuration.log_level
    GraphMediator::Configuration.log_level = ActiveSupport::BufferedLogger::DEBUG
  end

  after(:all) do
    #GraphMediator::Configuration.logger = @old_logger
    GraphMediator::Configuration.log_level = @old_log_level
  end

  before(:each) do
    load_traceable_callback_tester
    @t = Traceable.new(:name => :gizmo)
    @t.save_without_mediation! 
  end

  after(:each) do
    Object.__send__(:remove_const, :Traceable)
  end

  it "should only perform a single after_mediation even with nested mediated_transactions" do
    @t.mediated_transaction do
      @t.mediated_transaction {}
    end
    @traceables_callbacks.should == [:before, :reconcile, :cache]
  end

  it "should only perform a single after_mediation even with implicitly nested mediated transactions" do

    @t.mediated_transaction do
      @t.update_attributes(:name => 'foo')
    end
    @traceables_callbacks.should == [:before, :reconcile, :cache]
  end

  it "should call after_mediation only once even if mediated_transaction is called on a new instance" do
    Traceable.logger.debug "\n\n\nnew test"
    new_t = Traceable.new(:name => 'new')
    new_t.mediated_transaction { new_t.save }
    @traceables_callbacks.should == [:before, :reconcile, :cache]
  end

end
