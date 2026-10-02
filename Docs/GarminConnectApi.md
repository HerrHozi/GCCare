# Garmin Connect API Reference for `Invoke-GarminConnectApi`

```Text
Source:          garminconnect 0.3.17 (python-garminconnect) and demo.py of GCCare
Base URL:        https://connectapi.garmin.com
Authentication:  DI OAuth2 bearer token (gctoken.json, created by Get-GarminToken)
Helper:          GCCare\Private\GarminConnectApi.ps1
```

This is an unofficial API. Garmin can change endpoints at any time. Every endpoint below is
taken from the `garminconnect` Python library, so the right-hand column shows the matching
Python method in case you want to compare results.

## Contents

- [Usage](#usage)
- [Placeholders](#placeholders)
- [User Profile and Settings](#user-profile-and-settings)
- [Daily Summary, Steps and Floors](#daily-summary-steps-and-floors)
- [Heart Rate, Stress, Body Battery and Wellness](#heart-rate-stress-body-battery-and-wellness)
- [Sleep and HRV](#sleep-and-hrv)
- [Body Composition, Weight and Blood Pressure](#body-composition-weight-and-blood-pressure)
- [Hydration and Nutrition](#hydration-and-nutrition)
- [Training Metrics and Performance](#training-metrics-and-performance)
- [Biometrics, Zones and Thresholds](#biometrics-zones-and-thresholds)
- [Activities](#activities)
- [Activity Details](#activity-details)
- [Downloads and Uploads](#downloads-and-uploads)
- [Gear](#gear)
- [Badges and Challenges](#badges-and-challenges)
- [Goals and Personal Records](#goals-and-personal-records)
- [Devices](#devices)
- [Workouts and Calendar](#workouts-and-calendar)
- [Training Plans](#training-plans)
- [Women's Health](#womens-health)
- [Golf](#golf)
- [GraphQL](#graphql)
- [Helper Patterns](#helper-patterns)

## Usage

```powershell
# Simple GET
Invoke-GarminConnectApi -Path '/badge-service/badge/earned'

# GET with query parameters
Invoke-GarminConnectApi -Path '/activitylist-service/activities/search/activities' -Query @{ start = 0; limit = 20 }

# Array values become repeated parameters: metricId=22&metricId=23
Invoke-GarminConnectApi -Path "/userstats-service/wellness/daily/$displayName" -Query @{ fromDate = '2026-09-01'; untilDate = '2026-09-30'; metricId = 22, 23 }

# POST/PUT with JSON body
Invoke-GarminConnectApi -Path "/activity-service/activity/$activityId" -Method Put -Body @{ activityId = $activityId; activityName = 'Morning Run' }

# Download a file
Invoke-GarminConnectApi -Path "/download-service/export/tcx/activity/$activityId" -OutFile "$env:USERPROFILE\GCCare\activity_$activityId.tcx"

# Multipart upload
Invoke-GarminConnectApi -Path '/upload-service/upload' -Method Post -Form @{ file = Get-Item "$env:USERPROFILE\GCCare\FitFiles\weight.fit" }
```

| Parameter | Description |
| --- | --- |
| `-Path` | Endpoint path below `https://connectapi.garmin.com` (leading `/` optional) |
| `-Query` | Hashtable of query parameters; arrays are repeated, booleans sent as `true`/`false` |
| `-Method` | `Get` (default), `Post`, `Put`, `Delete` |
| `-Body` | Object or JSON string, sent as `application/json` |
| `-Form` | Hashtable for `multipart/form-data` uploads |
| `-OutFile` | Save raw response (FIT, TCX, GPX, KML, CSV, ZIP) instead of parsing JSON |
| `-TokenStore` | Token directory or `gctoken.json` (default: `$env:GARMINTOKENS`, then `~\.garminconnect`) |

## Placeholders

| Placeholder | Meaning | How to get it |
| --- | --- | --- |
| `{displayName}` | Garmin display name (URL-encoded) | `(Invoke-GarminConnectApi '/userprofile-service/socialProfile').displayName` |
| `{userProfilePk}` | Numeric user profile ID | `(Invoke-GarminConnectApi '/userprofile-service/socialProfile').profileId` |
| `{date}`, `{start}`, `{end}` | Date as `yyyy-MM-dd` | `(Get-Date).ToString('yyyy-MM-dd')` |
| `{activityId}` | Activity ID | `activityId` from the activity search |
| `{deviceId}` | Device ID | `deviceId` from `/device-service/deviceregistration/devices` |
| `{gearUUID}` | Gear UUID | `uuid` from `/gear-service/gear/filterGear` |
| `{workoutId}` | Workout ID | `workoutId` from `/workout-service/workouts` |
| `{sport}` | Sport key | e.g. `RUNNING`, `CYCLING` |

Timestamps in JSON bodies use local time with milliseconds: `(Get-Date).ToString('yyyy-MM-ddTHH:mm:ss.fff')`.
The matching GMT value: `(Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fff')`.

## User Profile and Settings

| Method | Endpoint | Query / Body | garminconnect |
| --- | --- | --- | --- |
| GET | `/userprofile-service/socialProfile` | - | `display_name`, `full_name` |
| GET | `/userprofile-service/userprofile/user-settings` | - | `get_user_profile` |
| GET | `/userprofile-service/userprofile/settings` | - | `get_userprofile_settings` |
| PUT | `/userprofile-service/userprofile/user-settings` | Body: settings object | `update_menstrual_settings` |

`get_unit_system` reads `userData.measurementSystem` from `/userprofile-service/userprofile/user-settings`.

```powershell
$social = Invoke-GarminConnectApi '/userprofile-service/socialProfile'
$displayName = [Uri]::EscapeDataString($social.displayName)
```

## Daily Summary, Steps and Floors

| Method | Endpoint | Query / Body | garminconnect |
| --- | --- | --- | --- |
| GET | `/usersummary-service/usersummary/daily/{displayName}` | `calendarDate={date}` | `get_user_summary`, `get_stats` |
| GET | `/wellness-service/wellness/dailySummaryChart/{displayName}` | `date={date}` | `get_steps_data` |
| GET | `/wellness-service/wellness/floorsChartData/daily/{date}` | - | `get_floors` |
| GET | `/usersummary-service/stats/steps/daily/{start}/{end}` | max. 28 days per call | `get_daily_steps` |
| GET | `/usersummary-service/stats/steps/weekly/{end}/{weeks}` | - | `get_weekly_steps` |
| GET | `/usersummary-service/stats/stress/weekly/{end}/{weeks}` | - | `get_weekly_stress` |
| GET | `/usersummary-service/stats/im/weekly/{start}/{end}` | - | `get_weekly_intensity_minutes` |
| GET | `/wellness-service/wellness/daily/im/{date}` | - | `get_intensity_minutes_data` |
| GET | `/wellness-service/wellness/dailyEvents` | `calendarDate={date}` | `get_all_day_events` |
| GET | `/lifestylelogging-service/dailyLog/{date}` | - | `get_lifestyle_logging_data` |
| POST | `/wellness-service/wellness/epoch/request/{date}` | - | `request_reload` |

```powershell
$today = (Get-Date).ToString('yyyy-MM-dd')
$summary = Invoke-GarminConnectApi "/usersummary-service/usersummary/daily/$displayName" -Query @{ calendarDate = $today }
'{0} steps, {1:N0} kcal' -f $summary.totalSteps, $summary.totalKilocalories
```

## Heart Rate, Stress, Body Battery and Wellness

| Method | Endpoint | Query / Body | garminconnect |
| --- | --- | --- | --- |
| GET | `/wellness-service/wellness/dailyHeartRate/{displayName}` | `date={date}` | `get_heart_rates` |
| GET | `/userstats-service/wellness/daily/{displayName}` | `fromDate`, `untilDate`, `metricId=60` | `get_rhr_day`, `get_rhr_daily` |
| GET | `/userstats-service/wellness/daily/{displayName}` | `fromDate`, `untilDate`, `metricId=22,23` | `get_calories_daily` (active + BMR) |
| GET | `/wellness-service/wellness/dailyStress/{date}` | - | `get_stress_data`, `get_all_day_stress` |
| GET | `/wellness-service/wellness/bodyBattery/reports/daily` | `startDate`, `endDate` | `get_body_battery` |
| GET | `/wellness-service/wellness/bodyBattery/events/{date}` | - | `get_body_battery_events` |
| GET | `/wellness-service/wellness/daily/respiration/{date}` | - | `get_respiration_data` |
| GET | `/wellness-service/wellness/daily/spo2/{date}` | - | `get_spo2_data` |

Resting heart rate values are in `allMetrics.metricsMap.WELLNESS_RESTING_HEART_RATE`;
calories in `WELLNESS_ACTIVE_CALORIES` and `WELLNESS_BMR_CALORIES`.

```powershell
$rhr = Invoke-GarminConnectApi "/userstats-service/wellness/daily/$displayName" -Query @{ fromDate = '2026-09-01'; untilDate = '2026-09-30'; metricId = 60 }
$rhr.allMetrics.metricsMap.WELLNESS_RESTING_HEART_RATE | Select-Object calendarDate, value
```

## Sleep and HRV

| Method | Endpoint | Query / Body | garminconnect |
| --- | --- | --- | --- |
| GET | `/wellness-service/wellness/dailySleepData/{displayName}` | `date={date}`, `nonSleepBufferMinutes=60` | `get_sleep_data` |
| GET | `/sleep-service/stats/sleep/daily/{start}/{end}` | max. 28 days per call, rows in `individualStats` | `get_sleep_daily` |
| GET | `/hrv-service/hrv/{date}` | - | `get_hrv_data` |
| GET | `/hrv-service/hrv/daily/{start}/{end}` | - | `get_hrv_data_range` |

## Body Composition, Weight and Blood Pressure

| Method | Endpoint | Query / Body | garminconnect |
| --- | --- | --- | --- |
| GET | `/weight-service/weight/dateRange` | `startDate`, `endDate` | `get_body_composition` |
| GET | `/weight-service/weight/range/{start}/{end}` | `includeAll=true` | `get_weigh_ins` |
| GET | `/weight-service/weight/dayview/{date}` | `includeAll=true` | `get_daily_weigh_ins` |
| POST | `/weight-service/user-weight` | Body: see below | `add_weigh_in` |
| DELETE | `/weight-service/weight/{date}/byversion/{weightPk}` | - | `delete_weigh_in` |
| POST | `/upload-service/upload` | Form: FIT file with weight scale message | `add_body_composition` |
| GET | `/bloodpressure-service/bloodpressure/range/{start}/{end}` | `includeAll=true` | `get_blood_pressure` |
| POST | `/bloodpressure-service/bloodpressure` | Body: see below | `set_blood_pressure` |
| DELETE | `/bloodpressure-service/bloodpressure/{date}/{version}` | - | `delete_blood_pressure` |

`delete_weigh_ins` reads the day view and deletes each `samplePk` with the DELETE endpoint above.

```powershell
# Add a weigh-in (kg)
$now = Get-Date
Invoke-GarminConnectApi '/weight-service/user-weight' -Method Post -Body @{
    dateTimestamp = $now.ToString('yyyy-MM-ddTHH:mm:ss.fff')
    gmtTimestamp  = $now.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fff')
    unitKey       = 'kg'
    sourceType    = 'MANUAL'
    value         = 78.4
}

# Add a blood pressure measurement
Invoke-GarminConnectApi '/bloodpressure-service/bloodpressure' -Method Post -Body @{
    measurementTimestampLocal = $now.ToString('yyyy-MM-ddTHH:mm:ss.fff')
    measurementTimestampGMT   = $now.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fff')
    systolic                  = 120
    diastolic                 = 80
    sourceType                = 'MANUAL'
    notes                     = ''
}
```

## Hydration and Nutrition

| Method | Endpoint | Query / Body | garminconnect |
| --- | --- | --- | --- |
| GET | `/usersummary-service/usersummary/hydration/daily/{date}` | - | `get_hydration_data` |
| PUT | `/usersummary-service/usersummary/hydration/log` | Body: `calendarDate`, `timestampLocal`, `valueInML` | `add_hydration_data` |
| GET | `/nutrition-service/food/logs/{date}` | - | `get_nutrition_daily_food_log` |
| GET | `/nutrition-service/meals/{date}` | - | `get_nutrition_daily_meals` |
| GET | `/nutrition-service/settings/{date}` | - | `get_nutrition_daily_settings` |

```powershell
Invoke-GarminConnectApi '/usersummary-service/usersummary/hydration/log' -Method Put -Body @{
    calendarDate   = (Get-Date).ToString('yyyy-MM-dd')
    timestampLocal = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss.fff')
    valueInML      = 500
}
```

## Training Metrics and Performance

| Method | Endpoint | Query / Body | garminconnect |
| --- | --- | --- | --- |
| GET | `/metrics-service/metrics/maxmet/daily/{start}/{end}` | - | `get_max_metrics`, `get_max_metrics_range` |
| GET | `/metrics-service/metrics/trainingreadiness/{date}` | - | `get_training_readiness`, `get_morning_training_readiness` |
| GET | `/metrics-service/metrics/trainingstatus/aggregated/{date}` | - | `get_training_status` |
| GET | `/metrics-service/metrics/trainingstatus/daily/{date}` | - | `get_daily_training_status` |
| GET | `/metrics-service/metrics/trainingloadbalance/latest/{date}` | - | `get_training_four_week_load_balance` |
| GET | `/metrics-service/metrics/endurancescore` | `calendarDate={date}` | `get_endurance_score` (single day) |
| GET | `/metrics-service/metrics/endurancescore/stats` | `startDate`, `endDate`, `aggregation=weekly` | `get_endurance_score` (range) |
| GET | `/metrics-service/metrics/hillscore` | `calendarDate={date}` | `get_hill_score` (single day) |
| GET | `/metrics-service/metrics/hillscore/stats` | `startDate`, `endDate`, `aggregation=daily` | `get_hill_score` (range) |
| GET | `/metrics-service/metrics/runningtolerance/stats` | `startDate`, `endDate`, `aggregation=daily\|weekly` | `get_running_tolerance` |
| GET | `/metrics-service/metrics/racepredictions/latest/{displayName}` | - | `get_race_predictions` (latest) |
| GET | `/metrics-service/metrics/racepredictions/{daily\|monthly}/{displayName}` | `fromCalendarDate`, `toCalendarDate` (max. 1 year) | `get_race_predictions` (range) |
| GET | `/fitnessage-service/fitnessage/{date}` | - | `get_fitnessage_data` |
| GET | `/fitnessstats-service/activity` | `startDate`, `endDate`, `aggregation=lifetime`, `groupByParentActivityType`, `metric` | `get_progress_summary_between_dates` |
| GET | `/fitnessstats-service/activity/all` | `startDate`, `endDate`, `metric` (array), `activityType` | `get_training_load_activities` |

`get_morning_training_readiness` picks the entry with `inputContext = 'AFTER_WAKEUP_RESET'`.
Typical `metric` values for training load: `activityTrainingLoad`, `trainingEffectLabel`, `trainingEffectLabelSrvrCalc`.

```powershell
$readiness = Invoke-GarminConnectApi "/metrics-service/metrics/trainingreadiness/$today"
$readiness | Where-Object inputContext -eq 'AFTER_WAKEUP_RESET' | Select-Object score, level
```

## Biometrics, Zones and Thresholds

| Method | Endpoint | Query / Body | garminconnect |
| --- | --- | --- | --- |
| GET | `/biometric-service/biometric/latestLactateThreshold` | - | `get_lactate_threshold` (latest) |
| GET | `/biometric-service/biometric/powerToWeight/latest/{date}` | `sport=Running` | `get_lactate_threshold` (latest) |
| GET | `/biometric-service/stats/lactateThresholdSpeed/range/{start}/{end}` | `sport=RUNNING`, `aggregation`, `aggregationStrategy=LATEST` | `get_lactate_threshold` (range) |
| GET | `/biometric-service/stats/lactateThresholdHeartRate/range/{start}/{end}` | `sport=RUNNING`, `aggregation`, `aggregationStrategy=LATEST` | `get_lactate_threshold` (range) |
| GET | `/biometric-service/stats/functionalThresholdPower/range/{start}/{end}` | `sport`, `aggregation=daily\|weekly\|monthly\|yearly`, `aggregationStrategy=LATEST` | `get_functional_threshold_power_range` |
| GET | `/biometric-service/biometric/latestFunctionalThresholdPower/CYCLING` | - | `get_cycling_ftp` |
| GET | `/biometric-service/heartRateZones` | - | `get_heart_rate_zones` |
| GET | `/biometric-service/powerZones/sports/all` | - | `get_power_zones` |
| GET | `/biometric-service/powerZones/sport/{sport}` | - | `get_power_zones_for_sport` |

## Activities

| Method | Endpoint | Query / Body | garminconnect |
| --- | --- | --- | --- |
| GET | `/activitylist-service/activities/search/activities` | `start`, `limit`, `activityType`, `activitySubType` | `get_activities`, `get_last_activity` |
| GET | `/activitylist-service/activities/search/activities` | `startDate`, `endDate`, `start`, `limit`, `activityType`, `sortOrder` | `get_activities_by_date` (paged by 20) |
| GET | `/activitylist-service/activities/count` | - | `count_activities` (`totalCount`) |
| GET | `/mobile-gateway/heartRate/forDate/{date}` | - | `get_activities_fordate` |
| GET | `/activity-service/activity/activityTypes` | - | `get_activity_types` |
| POST | `/activity-service/activity` | Body: manual activity, see below | `create_manual_activity`, `create_manual_activity_from_json` |
| PUT | `/activity-service/activity/{activityId}` | Body: `activityId`, `activityName` | `set_activity_name` |
| PUT | `/activity-service/activity/{activityId}` | Body: `activityId`, `description` | `set_activity_description` |
| PUT | `/activity-service/activity/{activityId}` | Body: `activityId`, `activityTypeDTO` | `set_activity_type` |
| DELETE | `/activity-service/activity/{activityId}` | - | `delete_activity` |

```powershell
# Last activity
$last = Invoke-GarminConnectApi '/activitylist-service/activities/search/activities' -Query @{ start = 0; limit = 1 } | Select-Object -Last 1
$last | Select-Object activityId, activityName, startTimeLocal, distance, duration

# All runs in September 2026 (paged)
$all = @(); $start = 0
do {
    $page = @(Invoke-GarminConnectApi '/activitylist-service/activities/search/activities' -Query @{
            startDate = '2026-09-01'; endDate = '2026-09-30'; activityType = 'running'; start = $start; limit = 20 })
    $all += $page; $start += 20
} while ($page.Count -gt 0)

# Rename an activity
Invoke-GarminConnectApi "/activity-service/activity/$($last.activityId)" -Method Put -Body @{ activityId = $last.activityId; activityName = 'Leutasch Trail' }

# Create a private manual activity
Invoke-GarminConnectApi '/activity-service/activity' -Method Post -Body @{
    activityTypeDTO      = @{ typeKey = 'running' }
    accessControlRuleDTO = @{ typeId = 2; typeKey = 'private' }
    timeZoneUnitDTO      = @{ unitKey = 'Europe/Berlin' }
    activityName         = 'Treadmill'
    metadataDTO          = @{ autoCalcCalories = $true }
    summaryDTO           = @{ startTimeLocal = '2026-09-30T07:00:00.000'; distance = 5000; duration = 1800 }
}
```

## Activity Details

| Method | Endpoint | Query / Body | garminconnect |
| --- | --- | --- | --- |
| GET | `/activity-service/activity/{activityId}` | - | `get_activity` |
| GET | `/activity-service/activity/{activityId}/details` | `maxChartSize=2000`, `maxPolylineSize=4000` | `get_activity_details` |
| GET | `/activity-service/activity/{activityId}/splits` | - | `get_activity_splits` |
| GET | `/activity-service/activity/{activityId}/typedsplits` | - | `get_activity_typed_splits` |
| GET | `/activity-service/activity/{activityId}/split_summaries` | - | `get_activity_split_summaries` |
| GET | `/activity-service/activity/{activityId}/weather` | - | `get_activity_weather` |
| GET | `/activity-service/activity/{activityId}/hrTimeInZones` | - | `get_activity_hr_in_timezones` |
| GET | `/activity-service/activity/{activityId}/powerTimeInZones` | - | `get_activity_power_in_timezones` |
| GET | `/activity-service/activity/{activityId}/exerciseSets` | - | `get_activity_exercise_sets` |
| PUT | `/activity-service/activity/{activityId}/exerciseSets` | Body: exercise sets | `set_activity_exercise_sets` |

```powershell
Invoke-GarminConnectApi "/activity-service/activity/$activityId/splits" |
    Select-Object -ExpandProperty lapDTOs |
    Select-Object lapIndex, distance, duration, averageHR, elevationGain
```

## Downloads and Uploads

| Method | Endpoint | Query / Body | garminconnect |
| --- | --- | --- | --- |
| GET | `/download-service/files/activity/{activityId}` | `-OutFile *.zip` (original FIT in ZIP) | `download_activity(ORIGINAL)` |
| GET | `/download-service/export/tcx/activity/{activityId}` | `-OutFile *.tcx` | `download_activity(TCX)` |
| GET | `/download-service/export/gpx/activity/{activityId}` | `-OutFile *.gpx` | `download_activity(GPX)` |
| GET | `/download-service/export/kml/activity/{activityId}` | `-OutFile *.kml` | `download_activity(KML)` |
| GET | `/download-service/export/csv/activity/{activityId}` | `-OutFile *.csv` | `download_activity(CSV)` |
| GET | `/download-service/files/wellness/{date}` | `-OutFile *.zip` | `download_health_snapshot` |
| POST | `/upload-service/upload` | Form: `file` | `upload_activity`, `add_body_composition` |
| POST | `/upload-service/upload/{fit\|gpx\|tcx}` | Form: `file`; 409 = duplicate | `import_activity` |

```powershell
# Download the original FIT file
Invoke-GarminConnectApi "/download-service/files/activity/$activityId" -OutFile "$env:USERPROFILE\GCCare\$activityId.zip"
Expand-Archive "$env:USERPROFILE\GCCare\$activityId.zip" -DestinationPath "$env:USERPROFILE\GCCare\FitFiles" -Force

# Upload FIT files (replacement for Send-FitFileToGarminConnect)
Get-ChildItem "$env:USERPROFILE\GCCare\FitFiles\*.fit" | ForEach-Object {
    Invoke-GarminConnectApi '/upload-service/upload/fit' -Method Post -Form @{ file = $_ }
}
```

## Gear

| Method | Endpoint | Query / Body | garminconnect |
| --- | --- | --- | --- |
| GET | `/gear-service/gear/filterGear` | `userProfilePk={userProfilePk}` | `get_gear` |
| GET | `/gear-service/gear/filterGear` | `activityId={activityId}` | `get_activity_gear` |
| GET | `/gear-service/gear/stats/{gearUUID}` | - | `get_gear_stats` |
| GET | `/gear-service/gear/user/{userProfilePk}/activityTypes` | - | `get_gear_defaults` |
| GET | `/activitylist-service/activities/{gearUUID}/gear` | `start=0`, `limit` | `get_gear_activities` |
| POST | `/gear-service/gear/v2` | Body: gear object | `create_gear` |
| PUT | `/gear-service/gear/{gearUUID}/activityType/{activityType}/default/true` | - | `set_gear_default(true)` |
| DELETE | `/gear-service/gear/{gearUUID}/activityType/{activityType}` | - | `set_gear_default(false)` |
| PUT | `/gear-service/gear/link/{gearUUID}/activity/{activityId}` | - | `add_gear_to_activity` |
| PUT | `/gear-service/gear/unlink/{gearUUID}/activity/{activityId}` | - | `remove_gear_from_activity` |

```powershell
$gear = Invoke-GarminConnectApi '/gear-service/gear/filterGear' -Query @{ userProfilePk = $social.profileId }
$gear | ForEach-Object {
    $stats = Invoke-GarminConnectApi "/gear-service/gear/stats/$($_.uuid)"
    [pscustomobject]@{ Name = $_.displayName; Km = [math]::Round($stats.totalDistance / 1000, 1); Activities = $stats.totalActivities }
}
```

## Badges and Challenges

| Method | Endpoint | Query / Body | garminconnect |
| --- | --- | --- | --- |
| GET | `/badge-service/badge/earned` | - | `get_earned_badges` (used by `Get-GarminBadges`) |
| GET | `/badge-service/badge/available` | `showExclusiveBadge=true` | `get_available_badges` |
| GET | `/badgechallenge-service/badgeChallenge/completed` | `start`, `limit` | `get_badge_challenges` |
| GET | `/badgechallenge-service/badgeChallenge/available` | `start`, `limit` | `get_available_badge_challenges` |
| GET | `/badgechallenge-service/badgeChallenge/non-completed` | `start`, `limit` | `get_non_completed_badge_challenges` |
| GET | `/badgechallenge-service/virtualChallenge/inProgress` | `start`, `limit` | `get_inprogress_virtual_challenges` |
| GET | `/adhocchallenge-service/adHocChallenge/historical` | `start`, `limit` | `get_adhoc_challenges` |

`get_in_progress_badges` combines earned and available badges where
`badgeProgressValue` is set and lower than `badgeTargetValue`:

```powershell
$earned    = @(Invoke-GarminConnectApi '/badge-service/badge/earned')
$available = @(Invoke-GarminConnectApi '/badge-service/badge/available' -Query @{ showExclusiveBadge = $true })
($earned + $available) |
    Where-Object { $_.badgeProgressValue -and $_.badgeTargetValue -and $_.badgeProgressValue -lt $_.badgeTargetValue } |
    Select-Object badgeName, badgeProgressValue, badgeTargetValue
```

## Goals and Personal Records

| Method | Endpoint | Query / Body | garminconnect |
| --- | --- | --- | --- |
| GET | `/goal-service/goal/goals` | `status=active\|future\|past`, `start`, `limit`, `sortOrder=asc` | `get_goals` |
| GET | `/personalrecord-service/personalrecord/prs/{displayName}` | - | `get_personal_record` |

## Devices

| Method | Endpoint | Query / Body | garminconnect |
| --- | --- | --- | --- |
| GET | `/device-service/deviceregistration/devices` | - | `get_devices` |
| GET | `/device-service/deviceservice/device-info/settings/{deviceId}` | - | `get_device_settings` (alarms in `alarms`) |
| GET | `/device-service/deviceservice/mylastused` | - | `get_device_last_used` |
| GET | `/web-gateway/device-info/primary-training-device` | - | `get_primary_training_device` |
| GET | `/web-gateway/solar/{deviceId}/{start}/{end}` | `singleDayView=true\|false` | `get_device_solar_data` |
| POST | `/device-service/devicemessage/messages` | Body: see Workouts | `push_workout_to_device` |

```powershell
# All alarms of all devices (get_device_alarms)
Invoke-GarminConnectApi '/device-service/deviceregistration/devices' | ForEach-Object {
    (Invoke-GarminConnectApi "/device-service/deviceservice/device-info/settings/$($_.deviceId)").alarms
}
```

## Workouts and Calendar

| Method | Endpoint | Query / Body | garminconnect |
| --- | --- | --- | --- |
| GET | `/workout-service/workouts` | `start`, `limit` | `get_workouts` |
| GET | `/workout-service/workout/{workoutId}` | - | `get_workout_by_id` |
| GET | `/workout-service/workout/FIT/{workoutId}` | `-OutFile *.fit` | `download_workout` |
| POST | `/workout-service/workout` | Body: workout JSON | `upload_workout`, `upload_*_workout` |
| PUT | `/workout-service/workout/{workoutId}` | Body: workout JSON | `update_workout` |
| DELETE | `/workout-service/workout/{workoutId}` | - | `delete_workout` |
| POST | `/workout-service/schedule/{workoutId}` | Body: `date` | `schedule_workout` |
| GET | `/workout-service/schedule/{scheduledWorkoutId}` | - | `get_scheduled_workout_by_id` |
| DELETE | `/workout-service/schedule/{scheduledWorkoutId}` | - | `unschedule_workout` |
| GET | `/calendar-service/year/{year}/month/{month-1}` | month is zero-based | `get_scheduled_workouts`, `get_next_scheduled_workout` |
| POST | `/device-service/devicemessage/messages` | Body: array, see below | `push_workout_to_device` |

```powershell
# Schedule a workout for tomorrow
Invoke-GarminConnectApi "/workout-service/schedule/$workoutId" -Method Post -Body @{ date = (Get-Date).AddDays(1).ToString('yyyy-MM-dd') }

# Calendar for October 2026 (month index 9)
(Invoke-GarminConnectApi '/calendar-service/year/2026/month/9').calendarItems | Where-Object itemType -eq 'workout'

# Send a workout to the watch
Invoke-GarminConnectApi '/device-service/devicemessage/messages' -Method Post -Body (ConvertTo-Json -Depth 5 -InputObject @(
    @{ deviceId = $deviceId; messageUrl = "workout-service/workout/FIT/$workoutId"; messageType = 'workouts'
       groupName = $null; messageName = 'Intervals'; priority = 1; fileType = 'FIT'; metaDataId = $workoutId }))
```

## Training Plans

| Method | Endpoint | Query / Body | garminconnect |
| --- | --- | --- | --- |
| GET | `/trainingplan-service/trainingplan/plans` | - | `get_training_plans` |
| GET | `/trainingplan-service/trainingplan/phased/{planId}` | - | `get_training_plan_by_id` |
| GET | `/trainingplan-service/trainingplan/fbt-adaptive/{planId}` | - | `get_adaptive_training_plan_by_id` |

## Women's Health

| Method | Endpoint | Query / Body | garminconnect |
| --- | --- | --- | --- |
| GET | `/periodichealth-service/menstrualcycle/dayview/{date}` | - | `get_menstrual_data_for_date` |
| GET | `/periodichealth-service/menstrualcycle/calendar/{start}/{end}` | - | `get_menstrual_calendar_data` |
| GET | `/periodichealth-service/menstrualcycle/lastconfirmed/{date}` | - | `get_menstrual_last_confirmed` |
| GET | `/periodichealth-service/menstrualcycle/summary/{date}` | - | `get_menstrual_cycle_summary` |
| GET | `/periodichealth-service/reports/menstrualcycle/{1\|6\|12}/{date}` | `next`, `reportType`, `todayCalendarDate` | `get_menstrual_reports` |
| GET | `/periodichealth-service/menstrualcycle/pregnancysnapshot` | - | `get_pregnancy_summary` |
| POST | `/periodichealth-service/menstrualcycle/dailylog/{date}` | Body: daily log | `update_menstrual_daily_log` |
| POST | `/periodichealth-service/menstrualcycle/calendarupdates` | Body: period dates | `update_menstrual_calendar` |
| POST | `/periodichealth-service/menstrualcycle/initCycleSetup` | Body: first period | `init_menstrual_cycle_setup` |
| POST | `/periodichealth-service/menstrualcycle/{periodStartDate}` | Body: period start | `confirm_menstrual_period_start` |

## Golf

| Method | Endpoint | Query / Body | garminconnect |
| --- | --- | --- | --- |
| GET | `/gcs-golfcommunity/api/v2/scorecard/summary` | `per-page`, `start` | `get_golf_summary` |
| GET | `/gcs-golfcommunity/api/v2/scorecard/detail` | `scorecard-ids`, `include-longest-shot-distance=true` | `get_golf_scorecard` |
| GET | `/gcs-golfcommunity/api/v2/shot/scorecard/{scorecardId}/hole` | `hole-numbers=1-2-3` | `get_golf_shot_data` |
| GET | `/gcs-golfcommunity/api/v2/club/player` | `per-page`, `include-stats=true` | `get_golf_club_stats` |
| GET | `/gcs-golfcommunity/api/v2/player/stats` | - | `get_golf_user_stats` |

## GraphQL

| Method | Endpoint | Query / Body | garminconnect |
| --- | --- | --- | --- |
| POST | `/graphql-gateway/graphql` | Body: `@{ query = '...' }` | `query_garmin_graphql` |

## Helper Patterns

Combined calls that the Python library builds from several endpoints:

| garminconnect | PowerShell equivalent |
| --- | --- |
| `get_stats_and_body` | Daily summary + `totalAverage` of `/weight-service/weight/dateRange` for the same date |
| `get_last_activity` | Activity search with `start=0`, `limit=1` |
| `get_in_progress_badges` | Earned + available badges, filtered by progress (see Badges) |
| `get_device_alarms` | Devices + device settings, collect `alarms` (see Devices) |
| `get_next_scheduled_workout` | Calendar of the current and next month, first workout on or after today |
| `get_daily_steps`, `get_sleep_daily` | Split ranges longer than 28 days into 28-day chunks |
| `delete_weigh_ins` | Day view, then DELETE every `samplePk` |
| `logout` | Delete `gctoken.json` |

```powershell
# Split a long date range into 28-day chunks (daily steps, daily sleep)
function Get-DateChunks([datetime]$Start, [datetime]$End, [int]$Days = 28) {
    for ($from = $Start; $from -le $End; $from = $to.AddDays(1)) {
        $to = @($from.AddDays($Days - 1), $End) | Sort-Object | Select-Object -First 1
        [pscustomobject]@{ Start = $from.ToString('yyyy-MM-dd'); End = $to.ToString('yyyy-MM-dd') }
    }
}

$steps = Get-DateChunks '2026-01-01' '2026-09-30' | ForEach-Object {
    Invoke-GarminConnectApi "/usersummary-service/stats/steps/daily/$($_.Start)/$($_.End)"
}
```
