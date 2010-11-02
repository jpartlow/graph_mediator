require File.expand_path(File.join(File.dirname(__FILE__), '..', 'spec_helper'))

require_reservations

class Reservation
  include GraphMediator
  mediate :dependencies => [Lodging, Party], 
    :when_reconciling => :reconcile,
    :when_cacheing => :cache
  def reconcile; :reconcile; end
  def cache; :cache; end
end

describe "GraphMediator locking scenarios" do

  before(:each) do
    @today = Date.today
    @handle1_r1 = Reservation.create!(:starts => @today, :ends => @today + 1, :name => 'foo')
    @handle2_r1 = Reservation.find(@handle1_r1.id)
  end

  it "should be possible to create an unattached dependent object" do
    Lodging.create!.should_not be_nil
  end

  context "with optimistic locking for the graph" do

    it "should raise Stale for conflicts updating root" do
      @handle2_r1.update_attributes(:name => 'bar')
      lambda { @handle1_r1.update_attributes(:name => 'baz') }.should raise_error(ActiveRecord::StaleObjectError)
      @handle1_r1.reload
      @handle1_r1.name.should == 'bar' 
    end

    # Creating root cannot conflict
    # because the rows do not exist until the mediation transaction completes
    # so no one else is in a position to write first

    # possible?
    it "should raise stale for conflicts deleting root"

    it "should raise Stale for conflicts creating children" do
      @handle2_r1.parties.create(:name => 'Bob')
      lambda { @handle1_r1.update_attributes(:name => 'baz') }.should raise_error(ActiveRecord::StaleObjectError)
    end

    context "with children" do
      
      before(:each) do
        @handle1_r1.mediated_transaction do
          @handle1_r1.parties.create(:name => 'Bob')
          @handle1_r1.parties.create(:name => 'Joe')
        end
        @handle2_r1.reload
      end

      it "should raise Stale for conflicts updating children and root" do
        @handle2_r1.parties.first.update_attributes(:name => 'Frank')
        lambda { @handle1_r1.update_attributes(:name => 'baz') }.should raise_error(ActiveRecord::StaleObjectError)
      end
 
      it "should raise Stale conflicts updating just children" do
        @handle2_r1.parties.first.update_attributes(:name => 'Frank')
        # version has incremented because of update to party, so, :versioning touch fails
        lambda { @handle1_r1.mediated_transaction {} }.should raise_error(ActiveRecord::StaleObjectError)
      end

      it "should raise Stale for conflicts deleting children and touching root" do
        @handle2_r1.parties.first.destroy
        lambda { @handle1_r1.update_attributes(:name => 'baz') }.should raise_error(ActiveRecord::StaleObjectError)
      end

    end

    context "within a mediated transaction" do

      it "should not raise stale for changes made within a mediated transaction"

      it "should not raise stale for counter_caches within a mediated transaction" do
        @handle1_r1.mediated_transaction do
          @handle1_r1.parties.create(:name => 'Bob')
          @handle1_r1.update_attributes(:name => 'baz')
        end
      end
    end
  end
end

module GraphMediatorLocking # namespace to prevent helper class conflicts

describe "GraphMediator locking scenarios for classes without counter_caches" do

  before(:all) do
    create_schema do |connection|
      connection.create_table(:foos, :force => true) do |t|
        t.string :name
        t.integer :lock_version, :default => 0
        t.timestamps
      end
  
      connection.create_table(:bars, :force => true) do |t|
        t.string :name
        t.belongs_to :foo
        t.integer :lock_version, :default => 0
        t.timestamps
      end
    end
  end

  class Bar < ActiveRecord::Base
    belongs_to :foo
  end

  class Foo < ActiveRecord::Base
    include GraphMediator
    mediate :dependencies => Bar
    has_many :bars
  end

  before(:each) do
    @h1_foo1 = Foo.create(:name => 'one')
    @h2_foo1 = Foo.find(@h1_foo1.id)
  end

  it "should also raise Stale for conflicts updating root" do
# nothing to touch...
    @h2_foo1.update_attributes(:name => 'bar')
    lambda { @h1_foo1.update_attributes(:name => 'baz') }.should raise_error(ActiveRecord::StaleObjectError)
    @h1_foo1.reload
    @h1_foo1.name.should == 'bar' 
  end

  it "should raise Stale for conflicts deleting children and touching root" do
    @h1_foo1.bars << Bar.create! 
    @h2_foo1.bars.first.destroy
    lambda { @h1_foo1.update_attributes(:name => 'baz') }.should raise_error(ActiveRecord::StaleObjectError)
  end

end

end
