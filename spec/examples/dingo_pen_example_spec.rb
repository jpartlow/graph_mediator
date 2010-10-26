require File.expand_path(File.join(File.dirname(__FILE__), 'spec_helper'))

# Okay I lied.  This example has dingos.

create_schema do |conn|
  
  conn.create_table(:dingo_pens, :force => true) do |t|
    t.integer :pen_number
    t.integer :dingo_count
    t.integer :biscuit_count
    t.integer :feed_rate
    t.float :total_biscuit_weight
    t.integer :dingo_pen_version
    t.integer :lock_version, :default => 0
    t.timestamps
  end
 
  conn.create_table(:dingos, :force => true) do |t|
    t.string :name
    t.string :breed
    t.integer :voracity
    t.integer :state
    t.integer :lock_version, :default => 0
    t.timestamps
  end

  conn.create_table(:biscuits, :force => true) do |t|
    t.string type
    t.float weight
    t.integer amount
    t.integer :lock_version, :default => 0
    t.timestamps
  end

end
