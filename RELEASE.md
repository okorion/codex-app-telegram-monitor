# 릴리스 체크리스트

[English](RELEASE.en.md)

이 저장소는 GitHub Release ZIP으로 배포할 수 있습니다. `vX.Y.Z` 형식의 tag를 push하면 릴리스 게시가 자동으로 실행됩니다.

1. `VERSION`을 업데이트합니다.
2. `CHANGELOG.md`에 `VERSION`과 같은 version 섹션을 추가합니다.
3. 검증을 실행합니다.

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

4. 추적되면 안 되는 로컬 상태 파일이 Git에 포함되지 않았는지 확인합니다.

```powershell
git ls-files .env logs state
```

5. `VERSION`과 일치하는 tag를 만듭니다.

```powershell
git tag v0.3.0
git push origin v0.3.0
```

6. GitHub Release workflow가 `VERSION`을 검증하고, `git archive`로 추적 파일만 포함한 ZIP을 만들고, `CHANGELOG.md`의 해당 version 섹션만 release notes로 게시합니다.

release artifact에는 `.env`, `logs/`, `state/`를 포함하지 마세요.
