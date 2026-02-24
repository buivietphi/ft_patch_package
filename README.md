# ft_patch_package

Patch Flutter & Dart packages like React Native's [patch-package](https://github.com/ds300/patch-package).

Make fixes to packages in `.pub-cache`, generate portable patch files, store them in version control, and apply them automatically after `flutter pub get`.

## Why?

When a Flutter package has a bug but the maintainer hasn't published a fix yet, you need a way to:
1. Apply your fix locally
2. Share the fix with your team
3. Survive `flutter pub get` / `flutter clean`

`ft_patch_package` solves this by creating **portable** patch files that work on any machine.

## Installation

```yaml
dev_dependencies:
  ft_patch_package: ^1.0.0
```

## Usage

### Step 1: Create a snapshot

```bash
dart run ft_patch_package start <package_name>
```

This saves the original state of the package before you edit it.

### Step 2: Make your changes

Edit the package files directly in `.pub-cache`:

```
~/.pub-cache/hosted/pub.dev/<package_name>-<version>/
```

### Step 3: Generate the patch

```bash
dart run ft_patch_package done <package_name>
```

This creates a portable patch file at `patches/<package_name>+<version>.patch`.

### Step 4: Commit & apply

```bash
# Commit the patches directory
git add patches/
git commit -m "Patch <package_name>: fix description"

# After flutter pub get, apply patches
dart run ft_patch_package apply
```

## Integration with Makefile

```makefile
rebuild:
	flutter clean
	flutter pub get
	dart run ft_patch_package apply
```

## Patch file format

Patch files use the `<package>+<version>.patch` naming convention:

```
patches/
├── health+13.3.1.patch
├── camera+0.10.6.patch
└── ...
```

Paths inside patch files use portable `a/` and `b/` prefixes (no machine-specific paths).

## Features

- **Portable patches** - No machine-specific paths. Works on any developer's machine.
- **Version-aware** - Matches exact package version from filename.
- **Idempotent** - Running `apply` multiple times won't break anything.
- **Version mismatch warnings** - Alerts when cached version differs from patch version.
- **Legacy support** - Works with unversioned `package.patch` filenames too.

## Improvements over patch_package

| Issue | patch_package | ft_patch_package |
|-------|--------------|-----------------|
| Portable paths | Machine-specific absolute paths | `a/` `b/` relative paths |
| Async handling | `void async` (process exits early) | `Future<void>` with await |
| Version matching | First regex match (wrong version) | Exact version from filename |
| Apply path bug | Relative `-i` path fails with `-d` | Absolute path for `-i` |
| Terminal output | `developer.log()` (invisible) | `print()` with colors |
| Idempotent apply | Fails on re-apply | Detects and skips |

## License

MIT
