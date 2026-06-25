# Release Checklist

[한국어](RELEASE.md)

This repository can be distributed as a GitHub Release ZIP. Publishing is automated for tags that match `vX.Y.Z`.

1. Update `VERSION`.
2. Add a matching version section to `CHANGELOG.md`.
3. Run validation:

```powershell
$scripts = Get-ChildItem -Filter *.ps1
foreach ($script in $scripts) {
  $tokens = $null
  $errors = $null
  [System.Management.Automation.Language.Parser]::ParseFile($script.FullName, [ref]$tokens, [ref]$errors) | Out-Null
  if ($errors.Count -gt 0) {
    throw "Parse failed: $($script.Name)"
  }
}

git diff --check
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\test_release_archive.ps1
```

4. Confirm ignored local state is not tracked:

```powershell
git ls-files .env logs state
```

5. Create a tag matching `VERSION`, for example:

```powershell
git tag v0.6.0
git push origin v0.6.0
```

6. The GitHub Release workflow validates `VERSION`, creates a tracked-file ZIP and SHA256 checksum through `test_release_archive.ps1`, and publishes only the matching `CHANGELOG.md` version section as release notes.

If needed, manually run the `릴리스` workflow in GitHub Actions and enter a `vX.Y.Z` tag to rerun the same publishing flow. If a release already exists for the same tag, the workflow updates the metadata and ZIP/checksum assets.

Do not include `.env`, `logs/`, or `state/` in release artifacts.
