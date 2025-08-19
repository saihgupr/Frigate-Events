# Auto-Retry Feature

## Overview

The Frigate Events app now includes an automatic retry feature that helps users reconnect to their Frigate server without manual intervention when network issues occur.

## How It Works

### Automatic Retry Logic

1. **Error Detection**: When a network error occurs, the app stores the timestamp of the error
2. **App Activation**: When the app becomes active again (e.g., after sleep, switching apps, etc.), it checks for recent errors
3. **Smart Retry**: If an error occurred within the last 5 minutes, the app automatically attempts to reconnect
4. **Success Handling**: When a successful connection is made, the error timestamp is cleared

### Key Features

- ✅ **Automatic**: No manual intervention required
- ✅ **Smart Timing**: Only retries for recent errors (within 5 minutes)
- ✅ **Non-Intrusive**: Retries happen in the background without showing loading indicators
- ✅ **Logging**: Console logs show when auto-retry is triggered
- ✅ **Persistent**: Works across app restarts and system sleep/wake cycles

## User Experience

### Before Auto-Retry
- User sees "Error: network error: could not connect to the server"
- User must manually press "Retry" button
- Frustrating experience, especially in the morning

### After Auto-Retry
- User sees the same error initially
- When they activate the app later, it automatically retries
- If connection is restored, the error disappears automatically
- Much smoother experience

## Technical Implementation

### Components

1. **App Level** (`Frigate_EventsApp.swift`):
   - Listens for `NSApplication.didBecomeActiveNotification`
   - Checks error timestamps
   - Triggers auto-retry notifications

2. **View Level** (`ContentView.swift`):
   - Listens for auto-retry notifications
   - Performs the actual retry
   - Manages error timestamps

3. **Data Storage**:
   - Uses `UserDefaults` to store `lastNetworkErrorTime`
   - Clears timestamp on successful connections

### Error Tracking

- **Stored**: `UserDefaults.standard.set(Date(), forKey: "lastNetworkErrorTime")`
- **Cleared**: `UserDefaults.standard.removeObject(forKey: "lastNetworkErrorTime")`
- **Checked**: On app activation to determine if retry is needed

### Retry Conditions

- Error must have occurred within the last 5 minutes
- App must become active (not just visible)
- Small delay (0.5 seconds) ensures app is fully ready

## Console Logging

The feature includes detailed console logging:

```
🔄 App became active - checking for auto-retry...
🔄 Auto-retrying connection after app became active...
🔄 Auto-retry triggered from notification
```

Or if no retry is needed:

```
🔄 App became active - checking for auto-retry...
🔄 Last error was 10 minutes ago - skipping auto-retry
🔄 No recent errors found - no auto-retry needed
```

## Benefits

1. **Improved UX**: Users don't need to manually retry connections
2. **Handles Common Scenarios**: Network interruptions, server restarts, sleep/wake cycles
3. **Smart Behavior**: Won't retry for old errors or persistent issues
4. **Transparent**: Works in the background without user awareness
5. **Reliable**: Uses proven notification system for app lifecycle events

## Future Enhancements

Potential improvements could include:
- Configurable retry intervals
- Retry count limits
- Different retry strategies for different error types
- User preference to enable/disable auto-retry
- Notification when auto-retry succeeds
