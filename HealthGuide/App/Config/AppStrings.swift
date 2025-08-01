//
//  AppStrings.swift
//  HealthGuide
//
//  All user-facing text for localization support
//  Extracted from mockups for consistency
//

import Foundation

@available(iOS 18.0, *)
struct AppStrings {
    
    // MARK: - App Name & Headers
    struct App {
        static let name = "HealthGuide"
        static let dashboard = "HealthGuide"
        static let todayFormat = "Today, %@"
        static let welcome = "Welcome to Careguide"
        static let tagline = "Smart health management."
    }
    
    // MARK: - Tab Bar
    struct TabBar {
        static let myHealth = "MyHealth"
        static let groups = "Groups"
        static let contacts = "Contacts"
        static let conflicts = "Conflicts"
    }
    
    // MARK: - Health Types
    struct HealthTypes {
        static let medication = "MEDICATION"
        static let supplement = "SUPPLEMENT"
        static let diet = "DIET"
    }
    
    // MARK: - Time Periods
    struct TimePeriods {
        static let breakfast = "Breakfast"
        static let lunch = "Lunch"
        static let dinner = "Dinner"
        static let bedtime = "Bedtime"
        static let current = "Current"
        static let upcoming = "Upcoming"
        static let completed = "Completed"
    }
    
    // MARK: - Status Messages
    struct Status {
        static let due = "Due"
        static let taken = "✓ Taken"
        static let timeFormat = "%@:%@ %@"  // 8:00 AM
        static let completedAt = "%@ • Completed"
        static let currentAt = "%@ • Current"
        static let upcomingAt = "%@ • Upcoming"
    }
    
    // MARK: - Add Item Screen
    struct AddItem {
        static let title = "Add Medication"
        static let supplementTitle = "Add Supplement"
        static let dietTitle = "Add Diet"
        static let typeLabel = "Type"
        static let nameLabel = "Name"
        static let medicationNameLabel = "Medication Name"
        static let supplementNameLabel = "Supplement Name"
        static let dietNameLabel = "Diet Item"
        static let namePlaceholder = "Start typing..."
        static let dosageLabel = "Dosage"
        static let dosagePlaceholder = "e.g., 500mg, 2 tablets, 10ml"
        static let notesLabel = "Notes (Optional)"
        static let frequencyLabel = "How often per day?"
        static let timesLabel = "Times to take"
        static let scheduleLabel = "Schedule for next 5 days"
        static let addButton = "Add to MyHealth"
        static let addMedicationButton = "Add Medication to Schedule"
        static let cannotAddButton = "Cannot Add - Limit Reached"
    }
    
    // MARK: - Frequency Options
    struct Frequency {
        static let once = "Once"
        static let twice = "Twice"
        static let threeTimes = "3 times"
        static let twiceDaily = "Twice Daily Selected"
        static let timesFormat = "%@ (%@) & %@ (%@)"  // Breakfast (8:00 AM) & Dinner (7:00 PM)
    }
    
    // MARK: - Schedule
    struct Schedule {
        static let todayFormat = "Today (%@)"
        static let tomorrowFormat = "Tomorrow (%@)"
        static let dateFormat = "%@"
        static let confirmationFormat = "✓ This will create %d medication reminders over %d days"
    }
    
    // MARK: - Validation Messages
    struct Validation {
        static let dailyLimitTitle = "Daily Limit Reached"
        static let dailyLimitMessage = "You already have 3 medications scheduled for today. For your safety, we limit medications to 3 per day.\n\nYou can edit existing medications or try again tomorrow."
        static let dailyLimitWarning = "⚠️ You already have 3 medications scheduled today. Maximum 3 per day allowed for safety."
        static let viewTodayButton = "View Today's Medications"
        static let editExistingButton = "Edit Existing Medication"
        static let foodSpecificWarning = "Please be more specific about taking with food or on empty stomach"
    }
    
    // MARK: - AI Suggestions
    struct AI {
        static let medicationSuggestionFormat = "%@ • Common: %@"  // Type 2 Diabetes • Common: 500mg, 850mg, 1000mg
        static let aiIndicator = "AI"
        static let processingRequest = "Processing your request..."
        static let usingIntelligence = "🤖 Using Apple Intelligence..."
        static let foundFormat = "Found: %@ scheduled for %@"
        static let loggedFormat = "✓ Logged: %d %@ tablet (%@) taken at %@"
    }
    
    // MARK: - Siri Integration
    struct Siri {
        static let whatMedications = "What medications should I take now?"
        static let responseFormat = "You need to take %@ now for %@."
        static let noMedications = "You have no medications scheduled right now."
        static let tookMedicine = "I took my blood pressure pill"
        static let whenNextDose = "When's my next dose?"
    }
    
    // MARK: - Authentication
    struct Auth {
        static let setupFaceID = "Setup Face ID"
        static let useFaceID = "Use Face ID to securely access your health data"
        static let enableFaceID = "Enable Face ID"
        static let tryAgain = "Try Face ID Again"
        static let usePasscode = "Use Passcode"
        static let faceIDNotRecognized = "Face ID Not Recognized"
        static let faceIDInstructions = "Please position your face within the frame and try again. Make sure your face is clearly visible."
        static let havingTrouble = "Having trouble? Check Settings > Face ID & Passcode"
    }
    
    // MARK: - Subscription
    struct Subscription {
        static let chooseYourPlan = "Choose Your Plan"
        static let startTrial = "Start your 7-day free trial"
        static let freeForDays = "Free for 7 days"
        static let fullAccess = "Full access to all features • Cancel anytime"
        static let annualPlan = "Annual Plan"
        static let monthlyPlan = "Monthly Plan"
        static let mostPopular = "MOST POPULAR"
        static let yearPrice = "$70"
        static let monthPrice = "$8.99"
        static let perYear = "/year"
        static let perMonth = "/month"
        static let saveFormat = "Save $%d vs Monthly"
        static let billedMonthly = "Billed monthly"
        static let startFreeTrialButton = "Start Free Trial"
        static let trialTerms = "Free for 7 days, then $70/year. Cancel anytime in Settings.\nSupports Apple Pay & Stripe payments."
    }
    
    // MARK: - Features
    struct Features {
        static let unlimited = "✓ Unlimited medications & supplements"
        static let familySharing = "✓ Family group sharing"
        static let aiConflicts = "✓ AI conflict detection"
        static let siriIntegration = "✓ Siri integration"
        static let allFeatures = "✓ All features included"
        static let cancelAnytime = "✓ Cancel anytime"
    }
    
    // MARK: - Conflicts
    struct Conflicts {
        static let title = "Conflicts"
        static let subtitle = "AI-powered safety checks"
        static let highPriority = "⚠️ High Priority"
        static let mediumPriority = "⚠️ Medium Priority"
        static let safe = "✓ Safe"
        static let checkedVia = "Checked via Claude AI • %@ ago"
        static let noInteractions = "No known interactions found. Safe to take together."
    }
    
    // MARK: - Loading
    struct Loading {
        static let loadingSchedule = "Loading your schedule..."
        static let loadingMedications = "Loading medications..."
        static let processingVoice = "Processing voice command..."
    }
    
    // MARK: - Errors
    struct Errors {
        static let genericTitle = "Something went wrong"
        static let tryAgain = "Please try again"
        static let networkError = "Check your internet connection"
        static let authenticationFailed = "Authentication failed"
    }
}