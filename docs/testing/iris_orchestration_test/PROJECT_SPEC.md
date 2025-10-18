# Contact Manager - Concurrent Development Test

## Overview
A simple command-line contact management system built in Elixir.

## Requirements
- Store contacts (name, email, phone, notes)
- Add new contacts
- Search contacts by name/email
- List all contacts
- Export contacts to JSON
- File-based persistence

## Architecture
The application will be split into 4 modules that can be developed concurrently:

### Task 1: Contact Data Model (lib/contact.ex)
**Provider: deepseek-coder:1.3b**

Create a Contact struct with:
- Fields: id, name, email, phone, notes, inserted_at
- Validation functions (valid_email?, valid_phone?)
- Constructor function (new/1)
- to_map/1 and from_map/1 for serialization

```elixir
defmodule Contact do
  @enforce_keys [:name, :email]
  defstruct [:id, :name, :email, :phone, :notes, :inserted_at]

  # Generate unique ID
  # Validate email format
  # Validate phone format
  # Convert to/from map for JSON
end
```

### Task 2: Storage Module (lib/storage.ex)
**Provider: codellama:latest**

Create a Storage module with:
- save/2 - Save contacts to JSON file
- load/1 - Load contacts from JSON file
- File path handling
- Error handling for file operations

```elixir
defmodule ContactManager.Storage do
  # Read contacts from JSON file
  # Write contacts to JSON file
  # Handle file errors gracefully
  # Create file if doesn't exist
end
```

### Task 3: ContactManager API (lib/contact_manager.ex)
**Provider: gemma3:latest**

Create ContactManager module with:
- add_contact/2 - Add a contact to the list
- find_by_name/2 - Search by name (case-insensitive)
- find_by_email/2 - Search by email
- list_all/1 - Return all contacts
- delete_contact/2 - Remove a contact by ID

```elixir
defmodule ContactManager do
  # Add contact to list
  # Search contacts
  # Delete contacts
  # List all contacts
  # Uses Contact struct and Storage module
end
```

### Task 4: CLI Interface (lib/cli.ex)
**Provider: deepseek-coder:1.3b**

Create CLI module with:
- Interactive menu system
- Commands: add, search, list, delete, export, quit
- Pretty output formatting
- User input handling

```elixir
defmodule ContactManager.CLI do
  # Main loop
  # Display menu
  # Handle user commands
  # Format output nicely
  # Integration with ContactManager API
end
```

## Expected Output
Each module should be independently functional and include:
- Complete implementation
- Basic error handling
- Documentation comments
- Example usage in comments

## Success Criteria
1. All 4 modules compile without errors
2. Modules integrate together successfully
3. Can add, search, list, and export contacts
4. Data persists across sessions
