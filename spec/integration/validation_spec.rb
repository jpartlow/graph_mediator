require File.expand_path(File.join(File.dirname(__FILE__), '..', 'spec_helper'))

describe "GraphMediator validation scenarios" do

  before(:each) do
    load_traceable_callback_tester
  end

  after(:each) do
    Object.__send__(:remove_const, :Traceable)
  end

  it "should not call after_mediation if validation fails" do
    t = Traceable.new
    t.save.should == false
    @traceables_callbacks.should == [:before]
  end

end
