//
//  ZoneProvider.swift
//  AmazingCloudKit
//
//  Created by Fernando Olivares on 23/04/20.
//  Copyright © 2020 Fernando Olivares. All rights reserved.
//

import Foundation
import CloudKit

public class CustomZoneCreator {
	
	private let container: CKContainer
	init(container: CKContainer) {
		self.container = container
	}
	
	public enum CreateZoneError: Error {
		case creationUnavailableInSharedDB
		case cloudKit(Error)
		case invalidStateNoZonesReturned
		case invalidStateNoZoneCreated
	}
	
	public func create(_ zone: ZoneName, completion: @escaping (Result<CKRecordZone.ID, CreateZoneError>) -> Void) {
		
		let zoneID = CKRecordZone.ID(zoneName: zone, ownerName: CKCurrentUserDefaultName)
		let zone = CKRecordZone(zoneID: zoneID)
		let uploadZoneOperation = CKModifyRecordZonesOperation(recordZonesToSave: [zone], recordZoneIDsToDelete: nil)
		uploadZoneOperation.modifyRecordZonesCompletionBlock = { possibleSavedZones, _, possibleError in
			
			guard possibleError == nil else {
				completion(.failure(.cloudKit(possibleError!)))
				return
			}
			
			guard let savedZones = possibleSavedZones else {
				completion(.failure(.invalidStateNoZonesReturned))
				return
			}
			
			guard let index = savedZones.firstIndex(of: zone) else {
				completion(.failure(.invalidStateNoZoneCreated))
				return
			}
			
			completion(.success(savedZones[index].zoneID))
		}
		
		container.privateCloudDatabase.add(uploadZoneOperation)
	}
}
