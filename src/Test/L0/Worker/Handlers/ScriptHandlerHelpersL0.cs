using System;
using GitHub.Runner.Worker.Handlers;
using Xunit;

namespace GitHub.Runner.Common.Tests.Worker.Handlers
{
    public sealed class ScriptHandlerHelpersL0
    {
        [Theory]
        [Trait("Level", "L0")]
        [Trait("Category", "Worker")]
        [InlineData("bash", "--noprofile --norc -e -o pipefail \"{0}\"")]
        [InlineData("sh", "-e \"{0}\"")]
        [InlineData("cmd", "/D /E:ON /V:OFF /S /C \"CALL \"{0}\"\"")]
        [InlineData("pwsh", "-command \". '{0}'\"")]
        [InlineData("powershell", "-command \". '{0}'\"")]
        [InlineData("python", "{0}")]
        public void GetScriptArgumentsFormat_ReturnsExpectedFormat(string scriptType, string expected)
        {
            var result = ScriptHandlerHelpers.GetScriptArgumentsFormat(scriptType);
            Assert.Equal(expected, result);
        }

        [Fact]
        [Trait("Level", "L0")]
        [Trait("Category", "Worker")]
        public void GetScriptArgumentsFormat_UnknownShell_ReturnsEmpty()
        {
            var result = ScriptHandlerHelpers.GetScriptArgumentsFormat("unknown_shell");
            Assert.Equal("", result);
        }

        [Fact]
        [Trait("Level", "L0")]
        [Trait("Category", "Worker")]
        public void GetScriptArgumentsFormat_IsCaseInsensitive()
        {
            var lower = ScriptHandlerHelpers.GetScriptArgumentsFormat("bash");
            var upper = ScriptHandlerHelpers.GetScriptArgumentsFormat("BASH");
            var mixed = ScriptHandlerHelpers.GetScriptArgumentsFormat("Bash");

            Assert.Equal(lower, upper);
            Assert.Equal(lower, mixed);
        }

        [Theory]
        [Trait("Level", "L0")]
        [Trait("Category", "Worker")]
        [InlineData("bash", "/path/with spaces/script.sh", "--noprofile --norc -e -o pipefail \"/path/with spaces/script.sh\"")]
        [InlineData("sh", "/path/with spaces/script.sh", "-e \"/path/with spaces/script.sh\"")]
        [InlineData("bash", "/simple/path.sh", "--noprofile --norc -e -o pipefail \"/simple/path.sh\"")]
        [InlineData("sh", "/simple/path.sh", "-e \"/simple/path.sh\"")]
        [InlineData("pwsh", "/path/with spaces/script.ps1", "-command \". '/path/with spaces/script.ps1'\"")]
        public void GetScriptArgumentsFormat_FormattedWithPath_ProducesQuotedResult(string scriptType, string path, string expected)
        {
            var format = ScriptHandlerHelpers.GetScriptArgumentsFormat(scriptType);
            var result = string.Format(format, path);
            Assert.Equal(expected, result);
        }

        [Theory]
        [Trait("Level", "L0")]
        [Trait("Category", "Worker")]
        [InlineData("bash")]
        [InlineData("sh")]
        [InlineData("cmd")]
        [InlineData("pwsh")]
        [InlineData("powershell")]
        [InlineData("python")]
        public void GetScriptArgumentsFormat_AllBuiltins_ContainPlaceholder(string scriptType)
        {
            var result = ScriptHandlerHelpers.GetScriptArgumentsFormat(scriptType);
            Assert.Contains("{0}", result);
        }

        [Theory]
        [Trait("Level", "L0")]
        [Trait("Category", "Worker")]
        [InlineData("bash", ".sh")]
        [InlineData("sh", ".sh")]
        [InlineData("cmd", ".cmd")]
        [InlineData("pwsh", ".ps1")]
        [InlineData("powershell", ".ps1")]
        [InlineData("python", ".py")]
        public void GetScriptFileExtension_ReturnsExpectedExtension(string scriptType, string expected)
        {
            var result = ScriptHandlerHelpers.GetScriptFileExtension(scriptType);
            Assert.Equal(expected, result);
        }

        [Fact]
        [Trait("Level", "L0")]
        [Trait("Category", "Worker")]
        public void GetScriptFileExtension_UnknownShell_ReturnsEmpty()
        {
            var result = ScriptHandlerHelpers.GetScriptFileExtension("unknown_shell");
            Assert.Equal("", result);
        }

        [Theory]
        [Trait("Level", "L0")]
        [Trait("Category", "Worker")]
        [InlineData("bash /path/to/bash --special", "bash", "/path/to/bash --special")]
        [InlineData("pwsh", "pwsh", "")]
        [InlineData("custom_shell -flag1 -flag2 {0}", "custom_shell", "-flag1 -flag2 {0}")]
        public void ParseShellOptionString_ParsesCorrectly(string input, string expectedCommand, string expectedArgs)
        {
            var (shellCommand, shellArgs) = ScriptHandlerHelpers.ParseShellOptionString(input);
            Assert.Equal(expectedCommand, shellCommand);
            Assert.Equal(expectedArgs, shellArgs);
        }

        [Theory]
        [Trait("Level", "L0")]
        [Trait("Category", "Worker")]
        [InlineData("cmd", "@echo off")]
        public void FixUpScriptContents_Cmd_PrependsEchoOff(string scriptType, string expectedPrefix)
        {
            var result = ScriptHandlerHelpers.FixUpScriptContents(scriptType, "echo hello");
            Assert.StartsWith(expectedPrefix, result);
            Assert.Contains("echo hello", result);
        }

        [Theory]
        [Trait("Level", "L0")]
        [Trait("Category", "Worker")]
        [InlineData("pwsh")]
        [InlineData("powershell")]
        public void FixUpScriptContents_PowerShell_AddsErrorHandling(string scriptType)
        {
            var result = ScriptHandlerHelpers.FixUpScriptContents(scriptType, "Get-Process");
            Assert.Contains("$ErrorActionPreference = 'stop'", result);
            Assert.Contains("Get-Process", result);
            Assert.Contains("LASTEXITCODE", result);
        }

        [Fact]
        [Trait("Level", "L0")]
        [Trait("Category", "Worker")]
        public void FixUpScriptContents_Bash_ReturnsUnmodified()
        {
            var original = "#!/bin/bash\necho hello";
            var result = ScriptHandlerHelpers.FixUpScriptContents("bash", original);
            Assert.Equal(original, result);
        }
    }
}
