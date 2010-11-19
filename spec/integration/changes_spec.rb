require File.expand_path(File.join(File.dirname(__FILE__), '..', 'spec_helper'))

describe "GraphMediator change tracking scenarios" do

  before(:all) do
    create_schema do |conn|
      conn.create_table(:changes_roots, :force => true) do |t|
        t.string :name
        t.string :state
        t.integer :changes_dependents_count
      end
      conn.create_table(:changes_dependents, :force => true) do |t|
        t.string :name
        t.integer :number
        t.belongs_to :changes_root
      end
    end
    
    class ChangesDependent < ActiveRecord::Base
      belongs_to :changes_root, :counter_cache => true
    end
    class ChangesRoot < ActiveRecord::Base
      cattr_accessor :tests
      has_many :changes_dependents
      include GraphMediator
      mediate :dependencies => [ChangesDependent]
      mediate_reconciles :reconciles do |instance| 
        instance.tests.call(instance) unless instance.tests.nil?
      end
      def reconciles; :reconciles; end
    end
  end

  before(:each) do
    ChangesRoot.tests = nil
    @today = Date.today
  end

  it "should track changes to mediated instance" do
    r = ChangesRoot.new(:name => :foo)
    r.save_without_mediation!
    r.state = :one
    changes = r.changes
    run = false
    r.tests = Proc.new do |instance|
      instance.changes.should == {}
      instance.mediated_changes.should == { ChangesRoot => { r.id => changes } }
      run = true
    end
    r.save!
    run.should be_true 
  end

  it "should track changes to a newly created mediated instance" do
    r = ChangesRoot.new(:name => :foo)
    changes = r.changes
    run = false
    r.tests = Proc.new do |instance|
      instance.should equal(r)
      instance.changes.should == {}
      instance.mediated_changes.should == { ChangesRoot => { :_created => [changes] } }
      run = true
    end
    r.save!
    run.should be_true
  end

  it "should track addition of a dependent" do
    r = ChangesRoot.new(:name => :foo)
    r.save_without_mediation!
    d = r.changes_dependents.build(:name => :bar)
    changes = d.changes
    run = false
    r.tests = Proc.new do |instance|
      instance.mediated_changes.should == { ChangesDependent => { :_created => [ changes ] } }
      run = true
    end
    d.save!
    run.should be_true
  end

  it "should track changes to a dependent" do
    r = ChangesRoot.new(:name => :foo)
    r.save_without_mediation!
    d = r.changes_dependents.create!(:name => :bar)
    d.number = 2
    changes = d.changes
    run = false
    r.tests = Proc.new do |instance|
      instance.mediated_changes.should == { ChangesDependent => { d.id => changes } }
      run = true
    end
    d.save!
    run.should be_true
  end

  it "should track deletion of a dependent" do
    r = ChangesRoot.new(:name => :foo)
    r.save_without_mediation!
    d = r.changes_dependents.create!(:name => :bar)
    run = false
    r.tests = Proc.new do |instance|
      instance.mediated_changes.should == { ChangesDependent => { :_destroyed => [d.id] } }
      run = true
    end
    d.destroy
    run.should be_true
  end

  it "should differentiate changes to attributes with the same name in different classes." do
    r = ChangesRoot.new(:name => :foo)
    r.save_without_mediation!
    d = r.changes_dependents.create!(:name => :bar)

    d.number = 3
    dep_changes = d.changes
    r.name = 'different'
    root_changes = r.changes
    run = false
    mediated_changes = nil
    r.tests = Proc.new do |instance|
      d.save!
      mediated_changes = instance.mediated_changes
      mediated_changes.should == { ChangesRoot => { r.id => root_changes }, ChangesDependent => { d.id => dep_changes } }
      run = true
    end
    r.save!
    run.should be_true
    mediated_changes.changed_name?.should be_true
    mediated_changes.attribute_changed?(:name, ChangesDependent).should be_false
    mediated_changes.changes_dependent_changed_name?.should be_false
    mediated_changes.changes_root_changed_name?.should be_true 

    r.state = :new_state
    root_changes = r.changes 
    d.name = 'also different'
    dep_changes = d.changes
    r.save!
    run.should be_true
    mediated_changes.changed_name?.should be_true
    mediated_changes.changes_dependent_changed_name?.should be_true
    mediated_changes.changes_root_changed_name?.should be_false
  end

  it "should handle attribute queries for classes that have had no changes recorded" do
    r = ChangesRoot.new(:name => :foo)
    r.save_without_mediation!
    run = false
    r.tests = Proc.new do |instance|
      mediated_changes = instance.mediated_changes
      mediated_changes.should == { ChangesRoot => { r.id => {} }}
      mediated_changes.changes_dependent_changed_name?.should be_false
      run = true
    end
    r.save! 
    run.should be_true 
  end

end
