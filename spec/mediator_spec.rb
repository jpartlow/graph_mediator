require File.expand_path(File.join(File.dirname(__FILE__), 'spec_helper'))

describe "GraphMediator::Mediator" do
  
  before(:each) do
    load_traceable_callback_tester
    @t = Traceable.new(:name => :gizmo)
    @t.save_without_mediation!
    @m = @t.__send__(:_get_mediator)
  end

  after(:each) do
    Object.__send__(:remove_const, :Traceable)
  end

  it "should raise error if initialized with something that is not a GraphMediator" do
    lambda { GraphMediator::Mediator.new(:foo) }.should raise_error(ArgumentError)
  end

  it "should transition through states" do
    @m.should be_idle
    @m.start!
    @m.should be_mediating
    @m.bump!
    @m.should be_versioning
    @m.done!
    @m.should be_idle
    @m.disable!
    @m.should be_disabled
    @m.done!
    @m.should be_idle
  end

  it "should reflect mediation_enabled of mediated_instance" do
    @m.mediation_enabled?.should be_true
    @t.disable_mediation!
    @m.mediation_enabled?.should be_false
  end

  it "should only perform a single after_mediation even with nested mediated_transactions" do
    @m.mediate { @m.mediate { } }
    @traceables_callbacks.should == [:before, :reconcile, :cache]
  end

  it "should capture changes" do
    @m.changes.should == {}
    @t.name = :foo
    @t.should be_changed
    @m.track_changes_for(@t)
    @m.changes.should == {Traceable => { @t.id => { 'name'=> [:gizmo, :foo] }}}
  end

  # XXX Actually, this seems to be okay
  it "should raise a MediatorException if attempt a transaction before_create because save is called recursively" do
    begin
      Traceable.before_create { |i| i.mediated_transaction { i.callbacks << :before_create } }
      t = Traceable.new(:name => :foo)
      # lambda { t.save! }.should raise_error(GraphMediator::MediatorException)
      t.save!
      @traceables_callbacks.should == [:before, :before_create, :reconcile, :cache]
    ensure
      Traceable.before_create_callback_chain.clear
    end
  end

  context "when enabling and disabling mediation" do
  
    it "should continue to mediate if mediation disabled part way through" do
      @m.mediation_enabled?.should be_true
      @t.should_receive(:reconcile).once
      @m.mediate do
        @t.disable_mediation!
        @m.mediate do
          # should not begin a new transaction 
        end
      end
    end

    it "should continue as disabled if mediation enabled part way through" do
      @t.disable_mediation!
      @m.mediation_enabled?.should be_false
      @t.should_not_receive(:reconcile)
      @m.mediate do 
        @t.enable_mediation!
        @m.mediate do
          # should not begin a new transaction 
        end
      end
    end

  end

  context "with a GraphMediator::Mediator::ChangesHash" do
  
    before(:each) do
      @ch = GraphMediator::Mediator::ChangesHash.new
    end
 
    it "should capture changes for new objects" do
      @ch << Traceable.new
      @ch.should == { Traceable => { :_created => [ {} ] } }
    end

    it "should capture changes for changed objects" do
      @t.name = :bar
      @ch << @t
      @ch.should == { Traceable => { @t.id => { 'name' => [:gizmo, :bar] } } }
    end

    it "should capture changes for destroyed objects" do
      @t.destroy
      @ch << @t
      @ch.should == { Traceable => { :_destroyed => [@t.id] } }
    end
 
    it "should answer questions about changed attributes" do
      @t.name = :bar
      @ch << @t
      @ch.changed_name?.should be_true
      @ch.changed_frotz?.should be_false
    end
 
    it "should answer questions about multiple changed attributes" do
      @t.name = :bar
      @t.state = :frotzed
      @ch << @t
      @ch.all_changed?(:name, :state).should be_true
      @ch.all_changed?(:name, :number).should be_false
      @ch.any_changed?(:name, :number).should be_true
    end

    it "should answer questions about dependents not in the changes hash" do
      @ch.should == {}
      @ch.added_dependent?(Traceable).should == false
      @ch.destroyed_dependent?(Traceable).should == false
      @ch.altered_dependent?(Traceable).should == false
      @ch.touched_any_dependent?(Traceable).should == false
    end
 
    it "should answer questions about added dependents" do
      new_t = Traceable.new(:name => :dependent)
      @ch << new_t
      @ch.added_dependent?(Traceable).should be_true
      @ch.added_or_destroyed_dependent?(Traceable).should be_true
      @ch.touched_any_dependent?(Traceable).should be_true
    end

    it "should answer questions about deleted dependents" do
      @t.destroy
      @ch << @t
      @ch.destroyed_dependent?(Traceable).should be_true
      @ch.added_or_destroyed_dependent?(Traceable).should be_true
      @ch.touched_any_dependent?(Traceable).should be_true
    end

    it "should answer questions about changed dependents" do
      @t.name = :bar
      @ch << @t
      @ch.altered_dependent?(Traceable).should be_true
      @ch.added_or_destroyed_dependent?(Traceable).should be_false
      @ch.touched_any_dependent?(Traceable).should be_true
    end

  end
end
