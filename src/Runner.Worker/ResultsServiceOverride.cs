using System;
using GitHub.Runner.Common;

namespace GitHub.Runner.Worker
{
    internal static class ResultsServiceOverride
    {
        public const string ResultsUrlVariable = "ACTIONS_RUNNER_RESULTS_URL";

        public static bool TryGetResultsServiceUrl(Tracing trace, out string resultsServiceUrl)
        {
            return TryGetResultsServiceUrl(Environment.GetEnvironmentVariable(ResultsUrlVariable), trace, out resultsServiceUrl);
        }

        public static bool TryGetResultsServiceUrl(string configuredUrl, Tracing trace, out string resultsServiceUrl)
        {
            resultsServiceUrl = null;
            if (string.IsNullOrWhiteSpace(configuredUrl))
            {
                return false;
            }

            if (!Uri.TryCreate(configuredUrl.Trim(), UriKind.Absolute, out var backend) ||
                (backend.Scheme != Uri.UriSchemeHttp && backend.Scheme != Uri.UriSchemeHttps))
            {
                trace.Warning($"'{ResultsUrlVariable}' value '{configuredUrl}' is not an absolute http or https URI. Artifacts and cache use the GitHub Results service.");
                return false;
            }

            // The actions call new URL(value).origin, so a path can never reach them.
            if (backend.AbsolutePath != "/" || !string.IsNullOrEmpty(backend.Query) || !string.IsNullOrEmpty(backend.Fragment))
            {
                trace.Warning($"'{ResultsUrlVariable}' path, query and fragment are dropped, because the actions keep only the origin. Using '{backend.GetLeftPart(UriPartial.Authority)}/'.");
            }

            resultsServiceUrl = backend.GetLeftPart(UriPartial.Authority) + "/";
            return true;
        }
    }
}
