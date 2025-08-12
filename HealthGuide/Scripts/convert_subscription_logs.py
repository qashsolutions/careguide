#!/usr/bin/env python3
"""
Convert SubscriptionManager print statements to AppLogger
This script will help us systematically replace all 59 print statements
"""

import re

# Mapping of print patterns to Logger replacements
replacements = [
    # Initialization and setup
    (r'print\("📱 SubscriptionManager: Initialized.*?"\)', 'AppLogger.subscription.debug("SubscriptionManager initialized with deferred StoreKit")'),
    (r'print\("🎧 Starting transaction listener.*?"\)', 'AppLogger.subscription.info("Starting transaction listener")'),
    (r'print\("🔍 Checking for unfinished transactions.*?"\)', 'AppLogger.subscription.debug("Checking for unfinished transactions")'),
    (r'print\("⚠️ SubscriptionManager already initialized.*?"\)', 'AppLogger.subscription.debug("SubscriptionManager already initialized - skipping")'),
    (r'print\("🛍️ Initializing SubscriptionManager.*?"\)', 'AppLogger.subscription.info("Initializing SubscriptionManager")'),
    (r'print\("📱 Running on device.*?"\)', 'AppLogger.subscription.debug("Running on device - initializing StoreKit")'),
    (r'print\("⚠️ Running in simulator.*?"\)', 'AppLogger.subscription.warning("Running in simulator - StoreKit may not work without Apple ID")'),
    (r'print\("🔧 Setting up StoreKit.*?"\)', 'AppLogger.subscription.debug("Setting up StoreKit components")'),
    (r'print\("📊 Checking subscription status.*?"\)', 'AppLogger.subscription.debug("Checking subscription status")'),
    (r'print\("📦 Loading products.*?"\)', 'AppLogger.subscription.debug("Loading products from App Store")'),
    (r'print\("✅ SubscriptionManager initialization complete"\)', 'AppLogger.subscription.success("SubscriptionManager initialization complete")'),
    
    # Transaction handling
    (r'print\("🎧 Transaction listener active.*?"\)', 'AppLogger.subscription.info("Transaction listener active")'),
    (r'print\("🛑 Transaction listener cancelled"\)', 'AppLogger.subscription.debug("Transaction listener cancelled")'),
    (r'print\("📦 Transaction update received"\)', 'AppLogger.subscription.debug("Transaction update received")'),
    (r'print\("🔄 Auto-renewable subscription transaction"\)', 'AppLogger.subscription.debug("Processing auto-renewable subscription")'),
    (r'print\("✅ Transaction finished and removed from queue"\)', 'AppLogger.subscription.debug("Transaction completed and finished")'),
    (r'print\("⚠️ Transaction listener ended"\)', 'AppLogger.subscription.warning("Transaction listener ended")'),
    
    # Products and pricing
    (r'print\("🔍 Attempting to load product ID: \\(.+?\\)"\)', r'AppLogger.subscription.debug("Loading product ID: \(\1, privacy: .public)")'),
    (r'print\("✅ Loaded \\(.+?\\) products"\)', r'AppLogger.subscription.success("Loaded \(\1) products")'),
    (r'print\("  - Product: \\(.+?\\), Price: \\(.+?\\)"\)', r'AppLogger.subscription.debug("Product: \(\1, privacy: .public), Price: \(\2, privacy: .public)")'),
    
    # Errors
    (r'print\("❌ (.+?)"\)', r'AppLogger.subscription.error("\1")'),
    (r'print\("⚠️ (.+?)"\)', r'AppLogger.subscription.warning("\1")'),
    
    # Success messages
    (r'print\("✅ (.+?)"\)', r'AppLogger.subscription.success("\1")'),
    
    # Debug with string interpolation
    (r'print\("🔍 (.+?)"\)', r'AppLogger.subscription.debug("\1")'),
    (r'print\("📦 (.+?)"\)', r'AppLogger.subscription.debug("\1")'),
    (r'print\("🔄 (.+?)"\)', r'AppLogger.subscription.debug("\1")'),
    (r'print\("🧹 (.+?)"\)', r'AppLogger.subscription.debug("\1")'),
    (r'print\("📱 (.+?)"\)', r'AppLogger.subscription.debug("\1")'),
    
    # Generic catch-all for remaining prints
    (r'print\("(.+?)"\)', r'AppLogger.subscription.debug("\1")'),
    (r'print\((.+?)\)', r'AppLogger.subscription.debug(\1)'),
]

print("Replacement patterns ready for SubscriptionManager.swift")
print(f"Total patterns: {len(replacements)}")