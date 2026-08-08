using module .\BaseConfiguration.psm1;
using module .\M365ServiceHealthHubDB.psm1;
using module .\Utility.psd1;
using module .\Utility.psm1;

<# 
    ConfigurationManager is split into BaseConfiguration and ConfigurationManager
    to avoid circular dependency caused by M365ServiceHeathHubDB module.
#>

class ConfigurationManager: BaseConfiguration
{ 
    static [string]$ReleaseMessageEndpoint = [ConfigurationManager]::GetConfigurationValue("ServiceHealthHub-ReleaseNotesEndpoint");
    static [string]$PostIncidentReviewStorage = [ConfigurationManager]::GetConfigurationValue("PostIncidentReview-Storage");

    static [string]$GraphApiAuthConfig = $env:GraphApiAuthConfig;
    static [string]$CopilotConnectorAuthConfig = $env:CopilotConnectorAuthConfig;
    static [string]$PowerAutomateAuthConfig = $env:PowerAutomateAuthConfig;
    static [string]$RehydrateRoadmapItems = $env:RehydrateRoadmapItems;
    static [string]$TaskManager = $env:TaskManager;
    static [string]$D365PPFilter = $env:D365PPFilter;
    static [string]$WebAppId = $env:WebAppId;
    static [System.Object]$TaskManagerConfig = $(dir env:"$($env:TaskManager).*")

    static [System.Object]$TranslatorConfig = @{
        "AzureTranslator.Enabled" = [Utility]::ParseBooleanValue([ConfigurationManager]::GetConfigurationValue("AzureTranslator-Enabled"));
        "AzureTranslator.SubscriptionKey" = [ConfigurationManager]::GetSecret("AzureTranslator-SubscriptionKey");
        "AzureTranslator.Region" = [ConfigurationManager]::GetConfigurationValue("AzureTranslator-ResourceLocation");
    }

    static [System.Object]$TextSummarizationConfig = @{
        "TextSummarization.Enabled" = [Utility]::ParseBooleanValue([ConfigurationManager]::GetConfigurationValue("LanguageService-Enabled"));
        "TextSummarization.Endpoint" = [ConfigurationManager]::GetConfigurationValue("LanguageService-Endpoint");
        "TextSummarization.SubscriptionKey" = [ConfigurationManager]::GetSecret("LanguageService-SubscriptionKey");
        "TextSummarization.SentenceCount" = [ConfigurationManager]::GetConfigurationValue("TextSummarization-SentenceCount");    
    }

    static [string]GetConfigurationValue(
        [string]$Name
    )
    {
        $db = [M365ServiceHealthHubDB]::new();
        return $db.GetConfigValue($Name);
    }

    static [string]GetTaskManagerConfigParameter(
        [string]$ConfigParameter
    )
    {
        $configEntry = [ConfigurationManager]::TaskManagerConfig | Where-Object Name -eq $ConfigParameter
        if ($null -eq $configEntry)
        {
            return "";
        } else {
            return $configEntry.Value;
        }
    }

    static [string]GetTranslatorConfigParameter(
        [string]$ConfigParameter
    )
    {
        return [ConfigurationManager]::TranslatorConfig."$ConfigParameter"
    }

    static [string]GetTextSummarizationConfigParameter(
        [string]$ConfigParameter
    )
    {
        return [ConfigurationManager]::TextSummarizationConfig."$ConfigParameter"
    }
}