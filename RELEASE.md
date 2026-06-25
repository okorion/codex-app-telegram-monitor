# Release Checklist

This repository can be distributed as a GitHub Release ZIP. Publishing is automated for tags that match `vX.Y.Z`.

1. Update `VERSION`.
2. Update `CHANGELOG.md`.
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
```

4. Confirm ignored local state is not tracked:

```powershell
git ls-files .env logs state
```

5. Create a tag matching `VERSION`, for example:

```powershell
git tag v0.2.0
git push origin v0.2.0
```

6. The GitHub Release workflow validates `VERSION`, creates a tracked-file ZIP with `git archive`, and publishes the release.

Do not include `.env`, `logs/`, or `state/` in release artifacts.
