# Expense Tracker

A comprehensive iOS app for tracking personal expenses, managing loans, and monitoring financial transactions.

## Features

- Track daily expenses and income
- Manage bank accounts and cash
- Handle personal loans with interest calculations
- Generate financial reports
- Export and import data
- Customizable transaction categories

## Version Management

The app uses semantic versioning (MAJOR.MINOR.PATCH):

- MAJOR version: Breaking changes
- MINOR version: New features
- PATCH version: Bug fixes

Current version: 1.1.0

## Development

### Requirements

- iOS 15.0+
- Xcode 13.0+
- Swift 5.5+

### Setup

1. Clone the repository
2. Open `Expense.xcodeproj` in Xcode
3. Build and run the project

### Version Updates

To update the app version, use the version management script:

```bash
# For major updates (breaking changes)
./Scripts/version_manager.sh major

# For minor updates (new features)
./Scripts/version_manager.sh minor

# For patch updates (bug fixes)
./Scripts/version_manager.sh patch
```

## License

This project is licensed under the MIT License - see the LICENSE file for details.
