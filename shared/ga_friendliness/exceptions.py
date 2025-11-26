"""
Exception hierarchy for ga_friendliness library.

All exceptions inherit from GAFriendlinessError for easy catching of library-specific errors.
"""


class GAFriendlinessError(Exception):
    """Base exception for ga_friendliness library."""

    pass


class OntologyValidationError(GAFriendlinessError):
    """Raised when ontology validation fails.
    
    Examples:
        - Missing required aspects in ontology
        - Invalid label for an aspect
        - Malformed ontology JSON structure
    """

    pass


class PersonaValidationError(GAFriendlinessError):
    """Raised when persona validation fails.
    
    Examples:
        - Invalid persona weights
        - Missing required persona fields
        - Weights don't sum to reasonable value
    """

    pass


class ReviewExtractionError(GAFriendlinessError):
    """Raised when LLM review extraction fails.
    
    Examples:
        - LLM API call failure
        - Output doesn't match expected schema
        - Parsing errors in structured output
    """

    pass


class StorageError(GAFriendlinessError):
    """Raised when database operations fail.
    
    Examples:
        - Database connection errors
        - Schema version mismatch
        - Write operation failures
        - Transaction rollback errors
    """

    pass


class FeatureMappingError(GAFriendlinessError):
    """Raised when feature mapping fails.
    
    Examples:
        - Invalid feature mapping configuration
        - Unknown aspect in mapping
        - Score normalization errors
    """

    pass


class BuildError(GAFriendlinessError):
    """Raised when build process fails.
    
    Examples:
        - Source loading errors
        - Pipeline processing failures
        - Resource cleanup errors
    """

    pass


class AIPRuleParsingError(GAFriendlinessError):
    """Raised when AIP rule parsing fails.
    
    Examples:
        - Malformed AIP text
        - LLM extraction failure for rules
        - Invalid rule structure
    """

    pass


class ConfigurationError(GAFriendlinessError):
    """Raised when configuration is invalid or missing.
    
    Examples:
        - Missing required configuration files
        - Invalid JSON in config files
        - Missing environment variables
    """

    pass


class CacheError(GAFriendlinessError):
    """Raised when cache operations fail.
    
    Examples:
        - Cache directory not writable
        - Cache corruption
        - Fetch failures when cache miss
    """

    pass

