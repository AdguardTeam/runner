using GitHub.Runner.Worker;
using Xunit;

namespace GitHub.Runner.Common.Tests.Worker
{
    public sealed class ResultsServiceOverrideL0
    {
        [Theory]
        [Trait("Level", "L0")]
        [Trait("Category", "Worker")]
        [InlineData(null, false, null)]
        [InlineData("", false, null)]
        [InlineData("   ", false, null)]
        [InlineData("not a uri", false, null)]
        [InlineData("/relative/path", false, null)]
        [InlineData("ftp://enot.int.agrd.dev", false, null)]
        [InlineData("https://enot.int.agrd.dev", true, "https://enot.int.agrd.dev/")]
        [InlineData("http://enot.service.agrd.dev:8181", true, "http://enot.service.agrd.dev:8181/")]
        [InlineData("https://enot.int.agrd.dev/", true, "https://enot.int.agrd.dev/")]
        [InlineData("https://enot.int.agrd.dev/prefix", true, "https://enot.int.agrd.dev/")]
        [InlineData("https://enot.int.agrd.dev?trace=1", true, "https://enot.int.agrd.dev/")]
        public void ResolvesResultsServiceUrl(string configuredUrl, bool expected, string expectedUrl)
        {
            using (TestHostContext hc = new TestHostContext(this, nameof(ResolvesResultsServiceUrl)))
            {
                var resolved = ResultsServiceOverride.TryGetResultsServiceUrl(configuredUrl, hc.GetTrace(), out var resultsServiceUrl);

                Assert.Equal(expected, resolved);
                Assert.Equal(expectedUrl, resultsServiceUrl);
            }
        }
    }
}
