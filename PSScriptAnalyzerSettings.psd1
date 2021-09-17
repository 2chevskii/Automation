@{
  Rules        = @{
    PSUseCompatibleSyntax = @{
      Enable         = $true
      TargetVersions = @(
        '7.0'
      )
    }
  }
  ExcludeRules = @('PSAvoidUsingUsernameAndPasswordParams', 'PSAvoidUsingPlainTextForPassword', 'PSAvoidUsingPositionalParameters', 'PSUseShouldProcessForStateChangingFunctions', 'PSUseApprovedVerbs')
}
