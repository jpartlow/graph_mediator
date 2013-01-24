create_schema do |connection|
  connection.create_table(:parents, :force => true) do |t|
    t.string :name
    t.integer :lock_version, :default => 0
    t.timestamps
  end

  connection.create_table(:reverse_parents, :force => true) do |t|
    t.string :name
    t.integer :lock_version, :default => 0
    t.timestamps
  end

  connection.create_table(:children, :force => true) do |t|
    t.integer :parent_id
    t.string :marker
  end

  connection.create_table(:reverse_children, :force => true) do |t|
    t.integer :reverse_parent_id
    t.string :marker
  end
end
