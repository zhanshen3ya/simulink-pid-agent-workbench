"""Strict configuration loading with legacy field compatibility."""

from .schema import AutoPidConfig, ConfigError, load_config

__all__ = ["AutoPidConfig", "ConfigError", "load_config"]
