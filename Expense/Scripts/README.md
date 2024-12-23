# Version Management

This directory contains scripts for managing the app's version numbers.

## Version Numbers

The app uses semantic versioning (MAJOR.MINOR.PATCH):

- MAJOR version: Breaking changes
- MINOR version: New features
- PATCH version: Bug fixes

## Usage

To update the app version, use the version_manager.sh script:

```bash
# For major updates (breaking changes)
./Scripts/version_manager.sh major

# For minor updates (new features)
./Scripts/version_manager.sh minor

# For patch updates (bug fixes)
./Scripts/version_manager.sh patch
```

## Examples

1. If current version is 1.0.0:
   - `major` → 2.0.0
   - `minor` → 1.1.0
   - `patch` → 1.0.1

2. If current version is 1.1.0:
   - `major` → 2.0.0
   - `minor` → 1.2.0
   - `patch` → 1.1.1

The build number will automatically increment with each version update.

## Git Integration

After updating the version:
1. Commit the version changes
2. Tag the commit with the new version
3. Push changes and tags to remote

Example:
```bash
./Scripts/version_manager.sh minor
git add .
git commit -m "Bump version to $(agvtool what-marketing-version)"
git tag "v$(agvtool what-marketing-version)"
git push && git push --tags
``` 