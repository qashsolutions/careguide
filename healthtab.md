# MyHealth Tab - Complete Documentation

## Overview
The MyHealth tab is the primary medication management interface in HealthGuide, designed for elder-friendly interaction with large touch targets, clear visual hierarchy, and time-aware medication scheduling. It manages medications, supplements, and dietary items with intelligent notification scheduling and tracking.

## Core Features

### 1. Time-Period Based Organization
- **Three Daily Periods**: Breakfast (6-11 AM), Lunch (11 AM-6 PM), Dinner (6 PM-6 AM)
- **Smart Highlighting**: Current time period is highlighted with blue border
- **Period-Specific Counts**: Badge shows number of items per period
- **Auto-Refresh**: Updates when transitioning between time periods

### 2. Medication Tracking
- **Mark as Taken**: One-tap checkbox to mark medications as completed
- **Visual Feedback**: Checkmark animation and color change on completion
- **Confirmation Dialog**: "Have you taken [medication name]?" with Yes/No options
- **Blue tinted alerts**: All interactive elements use blue tint for visibility

### 3. Lazy Notification System
- **Performance Optimized**: Notifications only setup after first item added
- **Three Daily Notifications**: 9:00 AM, 1:00 PM, 6:00 PM
- **Grouped Notifications**: All items for a period in single notification
- **Badge Management**: Shows count of pending medications, clears when all marked

## File Structure

### Primary Views

#### `/Views/Dashboard/MyHealthDashboardView.swift`
**Purpose**: Main dashboard interface for medication management
**Key Components**:
- `contentView`: Switches between loading, empty state, and dashboard content
- `allTimePeriodsView`: Displays all three time periods with their medications
- `timePeriodSection`: Individual period card with medications list
- `medicationRow`: Individual medication display with mark-taken button
- `emptyStateView`: Onboarding screen when no items exist
- `updateBadgeCount()`: Updates app badge based on unmarked items

**State Management**:
```swift
@StateObject private var viewModel = MyHealthDashboardViewModel()
@State private var selectedPeriods: [TimePeriod] = [.breakfast]
@State private var showAddItem = false
@State private var showTakeConfirmation = false
@State private var pendingDoseToMark: (item: any HealthItem, dose: ScheduledDose?)? = nil
@State private var tappedItemId: UUID? = nil
@State private var hasLoadedData = false

// Lazy notification setup
@AppStorage("hasHealthItems") private var hasHealthItems = false
@AppStorage("notificationsSetup") private var notificationsSetup = false
@AppStorage("lastNotificationCheck") private var lastNotificationCheck: Double = 0
```

#### `/Views/Dashboard/MyHealthDashboardViewModel.swift`
**Purpose**: Business logic and data management for dashboard
**Key Properties**:
```swift
@Published var allItems: [(item: any HealthItem, dose: ScheduledDose?)] = []
@Published var isLoading = true
@Published var error: AppError?
```

**Key Methods**:
- `loadData()`: Fetches and processes health data for today
- `markDoseTaken()`: Updates dose status and refreshes data
- `itemsForPeriod()`: Filters items by time period
- `getAllPeriodCounts()`: Returns count dictionary for badges

### Add Item Flow

#### `/Views/AddItem/AddItemView.swift`
**Purpose**: Universal interface for adding medications, supplements, and diet items
**Features**:
- Item type selector (Medication/Supplement/Diet)
- Apple Intelligence field suggestions
- Frequency selector (Once/Twice/Three times/Four times daily)
- Schedule selector (next 7 days)
- Validation and error handling
- Elder-friendly 60pt button height

#### `/Views/AddItem/AddItemViewModel.swift`
**Purpose**: Business logic for adding items with validation
**Key Validations**:
- Name required for all items
- Dosage required for medications/supplements
- Maximum 10 items per type
- Schedule must have correct period count for frequency

### Supporting Components

#### `/Views/Components/HealthCardView.swift`
**Purpose**: Reusable card component for displaying health items
**Features**:
- Color-coded headers (Blue: Medication, Green: Supplement, Light Blue: Diet)
- Status badges (Due, Taken, Current, Upcoming)
- 44pt minimum touch targets
- Liquid glass effects with ultraThinMaterial

#### `/Views/Components/TimePeriodSelector.swift`
**Purpose**: Time period selection interface
**Features**:
- Four periods: Breakfast, Lunch, Dinner, Bedtime
- Current period highlighting
- Item count badges
- Smooth selection animations

## Core Data Model

### Entities and Attributes

#### `MedicationEntity`
**Purpose**: Stores medication information
**Attributes**:
```swift
- id: UUID (unique identifier)
- name: String (medication name)
- dosage: String (e.g., "500mg")
- unit: String (e.g., "tablet", "ml", "capsule")
- frequency: String (daily frequency)
- notes: String? (optional notes)
- createdAt: Date
- updatedAt: Date
- isActive: Bool (true if currently being taken)
- scheduleData: Data? (encoded Schedule object)
```

#### `SupplementEntity`
**Purpose**: Stores supplement information
**Attributes**:
```swift
- id: UUID
- name: String
- dosage: String
- unit: String
- frequency: String
- notes: String?
- createdAt: Date
- updatedAt: Date
- isActive: Bool
- scheduleData: Data?
```

#### `DietEntity`
**Purpose**: Stores dietary items
**Attributes**:
```swift
- id: UUID
- name: String
- portion: String (e.g., "1 cup", "200g")
- category: String (e.g., "low-sodium", "diabetic-friendly")
- frequency: String
- notes: String?
- createdAt: Date
- updatedAt: Date
- isActive: Bool
- scheduleData: Data?
```

#### `DoseEntity`
**Purpose**: Tracks individual doses/scheduled times
**Attributes**:
```swift
- id: UUID
- scheduledTime: Date (when to take)
- actualTime: Date? (when actually taken)
- isTaken: Bool (completion status)
- period: String (breakfast/lunch/dinner)
- createdAt: Date

// Relationships
- medication: MedicationEntity? (optional relationship)
- supplement: SupplementEntity? (optional relationship)
- diet: DietEntity? (optional relationship)
```

**Computed Properties** (via extensions):
```swift
- medicationName: String? (from relationship)
- medicationDosage: String? (from relationship)
- supplementName: String? (from relationship)
- supplementDosage: String? (from relationship)
- dietName: String? (from relationship)
- dietPortion: String? (from relationship)
```

### Data Processing

#### `/Services/Dashboard/HealthDataProcessor.swift`
**Purpose**: Processes and transforms Core Data into view models
**Key Methods**:
- `processHealthDataForToday()`: Fetches all items with today's doses
- `markDoseTakenAndRefresh()`: Updates dose status and reprocesses
- `getCurrentTimePeriod()`: Determines current period based on time

**Data Flow**:
1. Fetch medications, supplements, diets from Core Data
2. Fetch today's doses for each item
3. Match doses with items
4. Sort by scheduled time
5. Calculate period counts
6. Return `ProcessedHealthData` structure

## Layout & Design

### Visual Hierarchy
```
MyHealth Dashboard
├── Navigation Bar
│   └── Add Button (+)
├── Time Period Cards (3)
│   ├── Period Header
│   │   ├── Icon & Name
│   │   └── Count Badge
│   └── Medications List
│       ├── Icon (Type-specific)
│       ├── Name & Dosage
│       └── Mark Taken Button
└── Empty State (if no items)
```

### Color Scheme
- **Medication**: Dark Blue (#007AFF)
- **Supplement**: Green (#34C759)
- **Diet**: Light Blue (#87CEEB)
- **Background**: Warm off-white gradient (#F8F8F8 to #FAFAFA)
- **Current Period**: Blue border highlight
- **Completed**: Green checkmark (#34C759)

### Typography
- **Headers**: Monaco font, headline size (increased for elders)
- **Medication Names**: Monaco, medicationName size (elder-optimized)
- **Dosages**: Monaco, medicationDose size (secondary text)
- **All text**: Minimum 17pt for readability

### Touch Targets
- **Minimum**: 44x44 points (Apple HIG compliance)
- **Buttons**: 60pt height for primary actions
- **Mark Taken**: 32pt icon with 44pt tap area

## Notification Integration

### Schedule
- **9:00 AM**: Morning medications (Breakfast items)
- **1:00 PM**: Afternoon medications (Lunch items)
- **6:00 PM**: Evening medications (Dinner items)

### Badge Management
- Sets badge count when notifications sent
- Updates badge when items marked as taken
- Clears badge when all items completed
- Persists across app launches

### Lazy Loading Strategy
1. Check if user has health items (`hasHealthItems` flag)
2. If yes, check if notifications setup (`notificationsSetup` flag)
3. Request permission if needed
4. Schedule notifications in background
5. Update flags to prevent redundant setup

## Performance Optimizations

### Memory Management
- Single data load on view appearance
- Debounced refresh (0.5s delay on pull-to-refresh)
- Lazy notification initialization
- Background task for notification setup

### State Management
- `hasLoadedData` flag prevents duplicate loads
- View model caches processed data
- Period counts calculated once per load
- Spotlight donation for system integration

## Error Handling

### Validation Errors
- Empty name validation
- Missing dosage for medications/supplements
- Daily limit exceeded (10 items per type)
- Schedule validation (periods must match frequency)

### System Errors
- Core Data fetch failures
- Notification permission denied
- Save failures with user-friendly messages

## Accessibility Features

### VoiceOver Support
- All buttons have accessibility labels
- Hints provided for complex interactions
- State changes announced (marked as taken)

### Elder-Friendly Design
- Large touch targets (44-60pt)
- High contrast colors
- Clear visual feedback
- Confirmation dialogs for important actions
- Monaco font for better readability

## Testing Considerations

### Key Test Scenarios
1. Add first medication - verify notification setup
2. Mark medication as taken - verify badge updates
3. Time period transitions - verify highlighting changes
4. Add 10+ items - verify limit enforcement
5. Background/foreground - verify state persistence

### Debug Logging
- Data loading: `"🔍 DEBUG: MyHealthDashboardView loading data"`
- Item counts: `"🔍 DEBUG: Loaded X items"`
- Marking taken: `"✅ Marking dose as taken for: [name]"`
- Notification setup: `"📱 Setting up notifications lazily..."`

## Future Enhancements

### Planned Features
- Medication history view
- Refill reminders
- Doctor appointment integration
- Medication interaction warnings
- Photo attachment for pills
- Export functionality for caregivers

### Technical Improvements
- Widget support for quick marking
- Siri shortcuts for common actions
- Apple Watch companion app
- iCloud sync for multiple devices