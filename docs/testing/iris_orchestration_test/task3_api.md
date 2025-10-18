# Task 3: ContactManager API Module

Create `lib/contact_manager.ex` with contact management API.

## Requirements
1. Create ContactManager module with these functions:
   - `add_contact/2` - Add a contact to the list, save to storage
   - `find_by_name/2` - Search contacts by name (case-insensitive substring match)
   - `find_by_email/2` - Search contacts by email (exact match)
   - `list_all/1` - Return all contacts from storage
   - `delete_contact/2` - Remove contact by ID, save updated list
   - `export_json/2` - Export contacts to JSON file

2. Integration:
   - Use Contact module for creating/validating contacts
   - Use Storage module for persistence
   - Handle storage errors gracefully

3. Business logic:
   - Prevent duplicate emails
   - Validate contact data before saving
   - Return clear error messages

## Implementation Details
- Default storage file: "/tmp/contacts.json"
- For search: use String.downcase and String.contains?
- For delete: use Enum.reject with matching ID
- Load before operations, save after modifications

## Example Usage (in comments)
```elixir
# {:ok, contact} = ContactManager.add_contact(%{name: "Jane", email: "jane@example.com"}, "/tmp/contacts.json")
# results = ContactManager.find_by_name("jane", "/tmp/contacts.json")
# {:ok, all} = ContactManager.list_all("/tmp/contacts.json")
```

Output: Complete Elixir module code with business logic
