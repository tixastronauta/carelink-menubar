import Foundation

@main struct NativeChecks {
    static func main() throws {
        L10n.choice = .portuguese  // assertions below use the Portuguese source strings
        let raw: [String: Any] = ["patientData": [
            "clientTimeZoneName": "Europe/Lisbon", "bgUnits": "MGDL", "lastSGTrend": "NONE",
            "lastSG": ["sg": 120, "timestamp": "2026-07-01T13:00:00"],
            "activeInsulin": ["amount": 0],
            "sgs": [["sg": 0], ["sg": 120, "timestamp": "2026-07-01T13:00:00"],
                    ["sg": 120, "timestamp": "2026-07-01T13:00:00"]]]]
        let snapshot = try NativeParser.snapshot(raw)
        precondition(snapshot.timestamp == "2026-07-01T12:00:00Z")
        precondition(snapshot.activeInsulin == 0 && snapshot.history.count == 1)
        precondition(snapshot.glucoseText == "120")
        precondition(!snapshot.hasDeviceStatus)
        var device = raw["patientData"] as! [String: Any]
        device["reservoirRemainingUnits"] = 112.5; device["reservoirLevelPercent"] = -1
        device["pumpBatteryLevelPercent"] = 255
        device["sensorDurationHours"] = 96
        let status = try NativeParser.snapshot(["patientData": device])
        precondition(status.reservoirUnits == 112.5 && status.pumpBatteryPercent == nil && status.sensorHoursLeft == 96)
        precondition(status.reservoirPercent == nil)
        device["reservoirLevelPercent"] = 59
        let filled = try NativeParser.snapshot(["patientData": device])
        precondition(filled.reservoirPercent == 59)
        device["pumpBatteryLevelPercent"] = 80
        let charged = try NativeParser.snapshot(["patientData": device])
        precondition(charged.pumpBatteryPercent == 80)
        precondition(charged.timeInRange == nil && charged.smartGuardText == nil && charged.connectionWarning == nil)
        device["timeInRange"] = 78; device["belowHypoLimit"] = 3; device["aboveHyperLimit"] = 19
        device["therapyAlgorithmState"] = ["autoModeShieldState": "SAFE_BASAL", "safeBasalDuration": 45]
        device["conduitInRange"] = true; device["conduitMedicalDeviceInRange"] = false; device["conduitSensorInRange"] = false
        device["pumpSuspended"] = true; device["isPumpCharging"] = 1
        let full = try NativeParser.snapshot(["patientData": device])
        precondition(full.timeInRange == TimeInRange(inRange: 78, below: 3, above: 19) && full.timeInRange?.meetsGoal == true)
        precondition(full.smartGuardText == "Basal segura (45min)")
        precondition(full.connectionWarning == "Bomba fora do alcance do telemóvel")
        precondition(full.pumpSuspended == true && full.pumpCharging == nil)
        device["timeInRange"] = 60; device["belowHypoLimit"] = 3
        device["sensorState"] = "NO_ERROR_MESSAGE"; device["systemStatusMessage"] = "WARM_UP"
        device["infusionStatus"] = "END_OF_LIFE"
        device["markers"] = [
            ["type": "INSULIN", "timestamp": "2026-07-01T12:30:00",
             "data": ["dataValues": ["deliveredFastAmount": "4.5", "activationType": "RECOMMENDED", "completed": true]]],
            ["type": "INSULIN", "timestamp": "2026-07-01T12:35:00",
             "data": ["dataValues": ["deliveredFastAmount": "0.3", "activationType": "AUTOCORRECTION", "completed": true]]],
            ["type": "INSULIN", "timestamp": "2026-07-01T12:40:00",
             "data": ["dataValues": ["deliveredFastAmount": "2.0", "completed": false]]],
            ["type": "MEAL", "timestamp": "2026-07-01T12:25:00", "data": ["dataValues": ["amount": 30]]],
            ["type": "AUTO_BASAL_DELIVERY", "timestamp": "2026-07-01T12:20:00", "data": ["dataValues": ["bolusAmount": "0.1"]]],
            ["type": "MEAL", "timestamp": "bad", "data": ["dataValues": ["amount": 20]]]]
        let marked = try NativeParser.snapshot(["patientData": device])
        precondition(marked.sensorWarning == "Sensor a aquecer" && marked.infusionWarning == "Trocar conjunto")
        precondition(marked.infusionTimeLeft == nil)
        device["infusionStatus"] = "NORMAL"; device["infusionRemainingDuration"] = 4319
        let fresh = try NativeParser.snapshot(["patientData": device])
        precondition(fresh.infusionWarning == nil && fresh.infusionTimeLeft == 4319 && fresh.hasDeviceStatus)
        device["infusionRemainingDuration"] = 0
        let expired = try NativeParser.snapshot(["patientData": device])
        precondition(expired.infusionMinutesLeft == nil)
        device["infusionStatus"] = "END_OF_LIFE"
        precondition(marked.markers.map(\.kind) == [.meal, .bolus, .autoCorrection])
        precondition(marked.markers[1].amount == 4.5 && marked.markers[0].amountText == "30g")
        precondition(ISO8601DateFormatter().string(from: marked.markers[0].date) == "2026-07-01T11:25:00Z")
        precondition(marked.pumpLimits == nil)
        device["limits"] = [["lowLimit": 70, "highLimit": 200, "kind": "LIMITS"]]
        let limited = try NativeParser.snapshot(["patientData": device])
        precondition(limited.pumpLimits == 70...200)
        device["limits"] = [["lowLimit": 200, "highLimit": 70]]
        let inverted = try NativeParser.snapshot(["patientData": device])
        precondition(inverted.pumpLimits == nil)
        var mmolAccount = device
        mmolAccount["bgUnits"] = "MMOLL"; mmolAccount["lastSG"] = ["sg": 126, "timestamp": "2026-07-01T13:00:00"]
        mmolAccount["sgs"] = [["sg": 126, "timestamp": "2026-07-01T13:00:00"]]
        mmolAccount["limits"] = [["lowLimit": 70, "highLimit": 200]]
        let mmolSnapshot = try NativeParser.snapshot(["patientData": mmolAccount])
        precondition(abs(mmolSnapshot.glucose! - 6.99) < 0.01 && mmolSnapshot.glucoseText == "7.0")
        precondition(mmolSnapshot.pumpLimits == 70...200)
        mmolAccount["lastSG"] = ["sg": 7.0, "timestamp": "2026-07-01T13:00:00"]
        mmolAccount["sgs"] = [["sg": 7.0, "timestamp": "2026-07-01T13:00:00"]]
        let trueMmol = try NativeParser.snapshot(["patientData": mmolAccount])
        precondition(trueMmol.glucose == 7.0)
        let inconsistent = try NativeParser.snapshot(["patientData": device])
        precondition(inconsistent.timeInRange == nil)
        precondition(NativeParser.timestamp("2026-10-25T01:30:00", zone: "Europe/Lisbon") == nil)
        precondition(NativeParser.timestamp("2026-03-29T01:30:00", zone: "Europe/Lisbon") == nil)
        precondition(NativeParser.timestamp("2026-10-28T13:00:00", zone: "Europe/Lisbon") == "2026-10-28T13:00:00Z")
        precondition(NativeParser.timestamp("2026-10-28T13:00:00", zone: nil) == nil)
        precondition(NativeParser.number(true) == nil)
        do { _ = try NativeParser.snapshot(["error":"bad"]); preconditionFailure() } catch {}
        let secret = Diagnostics.redact(["access_token":"a", "nested":["Refresh_Token":"r", "sg":120],
                                         "list":[["code":"c"]], "jwt":"eyJa.eyJb.sig", "username":"synthetic"]) as! [String: Any]
        precondition(secret["access_token"] as? String == Diagnostics.redacted)
        precondition((secret["nested"] as! [String: Any])["Refresh_Token"] as? String == Diagnostics.redacted)
        precondition((secret["nested"] as! [String: Any])["sg"] as? Int == 120)
        precondition(((secret["list"] as! [Any])[0] as! [String: Any])["code"] as? String == Diagnostics.redacted)
        precondition(secret["jwt"] as? String == Diagnostics.redacted && secret["username"] as? String == "synthetic")
        let camel = Diagnostics.redact(["refreshToken": "opaque", "clientSecret": "s", "tokenType": "Bearer", "sg": 1]) as! [String: Any]
        precondition(camel["refreshToken"] as? String == Diagnostics.redacted && camel["clientSecret"] as? String == Diagnostics.redacted)
        precondition(camel["sg"] as? Int == 1)
        let shape = Diagnostics.shape(["patientData": ["sgs": [["sg": 1], ["sg": 2, "kind": "x"]], "on": true, "none": NSNull()]])
        precondition(Set(shape) == ["patientData: object", "patientData.none: null", "patientData.on: boolean", "patientData.sgs: array",
                               "patientData.sgs[]: object", "patientData.sgs[].kind: string", "patientData.sgs[].sg: number"])
        precondition(!shape.contains { $0.contains(": x") || $0.contains("2") })
        let redirect = URL(string: "com.medtronic.carepartner:/sso")!
        let code = try OAuthFlow.code(from: URL(string: "com.medtronic.carepartner:/sso?code=abc&state=ok")!, redirect: redirect, state: "ok")
        precondition(code == "abc")
        for url in ["com.medtronic.carepartner:/other?code=abc&state=ok", "com.medtronic.carepartner:/sso?code=abc&state=no", "com.medtronic.carepartner:/sso?code=a&code=b&state=ok"] {
            do { _ = try OAuthFlow.code(from: URL(string:url)!, redirect: redirect, state:"ok"); preconditionFailure() } catch {}
        }
        precondition(OAuthFlow.challenge("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk") == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        precondition(NetworkPolicy.allows(method:"GET", url:Endpoints.user, body:nil))
        precondition(NetworkPolicy.allows(method:"POST", url:Endpoints.display, body:["username":"synthetic", "role":"patient"]))
        precondition(!NetworkPolicy.allows(method:"POST", url:Endpoints.display, body:["username":"synthetic", "role":"patient", "bolus":1]))
        precondition(NetworkPolicy.allows(method:"POST", url:Endpoints.display, body:["username":"synthetic", "role":"carepartner",
            "patientId":"synthetic-patient", "appVersion":ClientIdentity.appVersion, "os":ClientIdentity.os]))
        precondition(!NetworkPolicy.allows(method:"POST", url:Endpoints.display, body:["username":"synthetic", "role":"carepartner",
            "appVersion":"9.9", "os":ClientIdentity.os]), "Only the fixed client version may be declared")
        precondition(!NetworkPolicy.allows(method:"POST", url:Endpoints.display, body:["username":"synthetic", "role":"carepartner",
            "appVersion":ClientIdentity.appVersion, "os":"ios"]), "Only the fixed client OS may be declared")
        precondition(!NetworkPolicy.allows(method:"DELETE", url:Endpoints.user, body:nil))
        precondition(!NetworkPolicy.allows(method:"GET", url:URL(string:"https://example.com")!, body:nil))
        let stored = Tokens(accessToken:"synthetic", refreshToken:"old", clientID:"client")
        let rotated = try Tokens.response(["access_token":"new", "refresh_token":"rotated"], clientID:stored.clientID, previous:stored)
        precondition(rotated.refreshToken == "rotated")
        let header = Data("{}".utf8).base64EncodedString()
        let payload = Data("{\"token_details\":{\"preferred_username\":\"synthetic-user\",\"email\":\"synthetic@example.invalid\"}}".utf8).base64EncodedString()
        precondition(Tokens(accessToken:"\(header).\(payload).sig", refreshToken:"r", clientID:"c").accountName == "synthetic@example.invalid")
        precondition(stored.accountName == nil)
        let retained = try Tokens.response(["access_token":"new"], clientID:stored.clientID, previous:stored)
        precondition(retained.refreshToken == "old")
        print("PASS: native normalization, optional device status, time in range, SmartGuard, connection, sensor/infusion status and time left, bolus and meal markers, pump limits, mmol plausibility, diagnostics redaction and shape, DST, schema rejection, OAuth state/callback/PKCE, read-only network policy and token rotation")
    }
}
