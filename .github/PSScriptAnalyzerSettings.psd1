@{
    Severity = @('Error', 'Warning')
    ExcludeRules = @(
        # Status text is the command-line interface.
        'PSAvoidUsingWriteHost'
        # -Setup, -Add and the updater switches are explicit commands.
        'PSUseShouldProcess'
    )
}
