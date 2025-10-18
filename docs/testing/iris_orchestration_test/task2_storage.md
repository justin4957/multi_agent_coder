# Task 2: Storage Module

Create `lib/storage.ex` with file-based contact persistence.

## Requirements
1. Create a ContactManager.Storage module with:
   - `save/2` - Save list of contacts to JSON file
   - `load/1` - Load contacts from JSON file
   - `ensure_file_exists/1` - Create empty file if doesn't exist
   - `file_path/1` - Generate file path from base name

2. File operations:
   - Store contacts as JSON array
   - Handle missing files gracefully (return empty list)
   - Handle corrupted JSON gracefully (return error)
   - Use Jason for JSON encoding/decoding

3. Error handling:
   - Return {:ok, data} or {:error, reason} tuples
   - Log errors but don't crash

## Implementation Details
- Default file path: "/tmp/contacts.json"
- Use File.read!/File.write for file I/O
- Use Jason.encode!/Jason.decode! for JSON
- Create directory if doesn't exist (File.mkdir_p!)

## Example Usage (in comments)
```elixir
# Storage.save([%{name: "John"}], "/tmp/contacts.json")
# {:ok, contacts} = Storage.load("/tmp/contacts.json")
```

Output: Complete Elixir module code with error handling
