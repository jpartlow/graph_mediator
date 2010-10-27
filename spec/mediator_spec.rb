require File.expand_path(File.join(File.dirname(__FILE__), 'spec_helper'))

require_reservations

class Reservation
  include GraphMediator
  mediate :when_reconciling => :reconcile,
    :when_cacheing => :cache,
    :when_bumping => :bump      
  def reconcile; :reconcile; end
  def cache; :cache; end
  def bump; :bump; end
end

describe "GraphMediator::Mediator" do
  
  before(:each) do
    @today = Date.today
    @r = Reservation.new(:starts => @today, :ends => @today + 1, :name => :foo)
    @r.save_without_mediation!
    @m = GraphMediator::Mediator.new(@r)
  end

  it "should raise error if initialized with something that is not a GraphMediator" do
    lambda { GraphMediator::Mediator.new(:foo) }.should raise_error(ArgumentError)
  end

  it "should transition through states" do
    @m.should be_idle
    @m.start!
    @m.should be_mediating
    @m.done!
    @m.should be_idle
    @m.disable!
    @m.should be_disabled
    @m.done!
    @m.should be_idle
  end

  it "should reflect mediation_enabled of mediated_instance" do
    @m.mediation_enabled?.should be_true
    @r.disable_mediation!
    @m.mediation_enabled?.should be_false
  end

  context "when enabling and disabling mediation" do
  
    it "should continue to mediate if mediation disabled part way through" do
      @m.mediation_enabled?.should be_true
      @r.should_receive(:reconcile).once
      @m.mediate do
        @r.disable_mediation!
        @m.mediate do
          # should not begin a new transaction 
        end
      end
    end

    it "should continue as disabled if mediation enabled part way through" do
      @r.disable_mediation!
      @m.mediation_enabled?.should be_false
      @r.should_not_receive(:reconcile)
      @m.mediate do 
        @r.enable_mediation!
        @m.mediate do
          # should not begin a new transaction 
        end
      end
    end

  end

end
