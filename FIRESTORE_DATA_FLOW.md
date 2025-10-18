# Firestore Data Flow

## Collections

### 1. families/{familyId}
Main family document

### 2. families/{familyId}/meals/{date}
Daily meal records

### 3. families/{familyId}/recordings/{date}
Daily voice/photo recordings

### 4. connection_codes/{codeId}
4-digit connection codes for linking parent & child apps

### 5. subscriptions/{userId}
User subscription status

---

## Parent App (Elderly Device)

### Setup Flow
1. User enters name "김할머니"
2. Click "설정 완료" button
3. **CREATE** `families/{randomFamilyId}`
   - familyId: "family_abc123"
   - connectionCode: "4943" (random 4-digit)
   - elderlyName: "김할머니"
   - createdBy: {userId}
   - memberIds: [{userId}]
   - isActive: true
   - approved: null

4. **CREATE** `connection_codes/{randomId}`
   - code: "4943"
   - familyId: "family_abc123"
   - elderlyName: "김할머니"
   - isActive: true
   - createdAt: timestamp

5. Show 4-digit code "4943" and wait

### Record Meal
1. User taps meal button (아침/점심/저녁/간식)
2. **UPDATE** `families/{familyId}`
   - lastMeal.timestamp: current time
   - lastMeal.count: +1
   - lastPhoneActivity: current time

3. **CREATE/UPDATE** `families/{familyId}/meals/{today}`
   - meals: [{timestamp, elderlyName, mealType}]

### GPS Tracking
Every 15 minutes (background):
1. Get current location
2. **UPDATE** `families/{familyId}`
   - location.latitude: 37.xxx
   - location.longitude: 127.xxx
   - location.timestamp: current time
   - lastLocationUpdate: current time

### Survival Signal
Every 2 minutes (background):
1. Check last activity
2. If > 24 hours inactive:
   - **UPDATE** `families/{familyId}`
     - alerts.survival: timestamp
     - alertsTriggered.survival: {timestamp, triggeredBy}

---

## Child App (Guardian Device)

### Connection Flow
1. User enters code "4943"
2. **QUERY** `connection_codes` WHERE code == "4943" AND isActive == true
3. Get familyId from result
4. **READ** `families/{familyId}`
5. Show family info and ask approval

### Approve Connection
1. User clicks "승인"
2. **UPDATE** `families/{familyId}`
   - approved: true
   - approvedAt: timestamp
   - approvedBy: {childUserId}
   - memberIds: [{parentUserId}, {childUserId}]

3. **UPDATE** `connection_codes/{codeId}`
   - isActive: false
   - usedAt: timestamp
   - usedBy: {childUserId}

4. Parent app receives notification → proceeds to main screen

### Monitor Status
Real-time listener on `families/{familyId}`:
- **READ** lastMeal.timestamp
- **READ** lastMeal.count
- **READ** alerts.survival
- **READ** location
- **READ** lastPhoneActivity

### View Meals
1. **READ** `families/{familyId}/meals/{date}`
2. Show list of meals with timestamps

### Clear Alert
1. User taps "확인" on survival alert
2. **UPDATE** `families/{familyId}`
   - alerts.survival: null
   - alertsCleared.survival: timestamp
   - lastPhoneActivity: current time

---

## Data Examples

### Family Document
```
families/family_abc123
{
  familyId: "family_abc123",
  connectionCode: "4943",
  elderlyName: "김할머니",
  createdBy: "uid_parent",
  memberIds: ["uid_parent", "uid_child"],
  isActive: true,
  approved: true,
  lastMeal: {
    timestamp: "2025-10-18T14:30:00Z",
    count: 2
  },
  location: {
    latitude: 37.5665,
    longitude: 126.9780,
    timestamp: "2025-10-18T15:00:00Z",
    address: "서울특별시 중구"
  },
  alerts: {
    survival: null
  },
  lastPhoneActivity: "2025-10-18T15:05:00Z"
}
```

### Meal Document
```
families/family_abc123/meals/2025-10-18
{
  meals: [
    {
      timestamp: "2025-10-18T08:00:00Z",
      elderlyName: "김할머니",
      mealType: "아침"
    },
    {
      timestamp: "2025-10-18T12:30:00Z",
      elderlyName: "김할머니",
      mealType: "점심"
    }
  ]
}
```

### Connection Code
```
connection_codes/xyz789
{
  code: "4943",
  familyId: "family_abc123",
  elderlyName: "김할머니",
  isActive: false,
  createdAt: "2025-10-18T10:00:00Z",
  usedAt: "2025-10-18T10:15:00Z",
  usedBy: "uid_child"
}
```

---

## Delete Flow

### Child App Deletes Account
1. User clicks delete
2. **UPDATE** `families/{familyId}`
   - isActive: false
3. **DELETE** all local data
4. Show confirmation

### Parent App Resets
1. User clicks reset
2. **DELETE** `families/{familyId}`
3. **DELETE** all subcollections (meals, recordings)
4. **DELETE** `connection_codes` where familyId matches
5. Return to setup screen
