//
//  CustomZoneFetcherService.swift
//  AmazingCloudKit
//
//  Created by Fernando Olivares on 24/04/20.
//  Copyright © 2020 Fernando Olivares. All rights reserved.
//

import Foundation
import CloudKit

// In order to keep `CustomZoneFetcher` internal, this must be a public enum outside its class.
public enum ZoneExistsError : Error {
	case cloudKit(Error)
	case invalidStateNoZonesReturned
	case invalidStateNoZoneInformation
	case invalidStateZoneFoundButNoIDAssociated
	case zoneNotFound
	case zoneDoesNotBelongToProvider
	case noZonesInProvider
}

public struct AmazingZone : Equatable {
	public let name: ZoneName
	public let read: ReadableZone
	public let write: WritableZone
	
	init(database: CKDatabase, zoneID: CKRecordZone.ID) {
		name = zoneID.zoneName
		read = ReadableZone(database: database, zoneID: zoneID)
		write = WritableZone(database: database, zoneID: zoneID)
	}
}

class CustomZoneFetcher {
	
	private let database: CKDatabase
	init(database: CKDatabase) {
		self.database = database
	}
	
	func fetch(completion: @escaping (Result<[ZoneName: AmazingZone], ZoneExistsError>) -> Void) {
		
		let zoneCheckOperation = CKFetchRecordZonesOperation.fetchAllRecordZonesOperation()
		zoneCheckOperation.fetchRecordZonesCompletionBlock = { possibleRecordZonesDictionary, possibleError in
			
			guard possibleError == nil else {
				completion(.failure(.cloudKit(possibleError!)))
				return
			}
			
			guard var recordZoneDictionary = possibleRecordZonesDictionary else {
				completion(.failure(.invalidStateNoZoneInformation))
				return
			}
			
			// Do not return the default zone.
			recordZoneDictionary.removeValue(forKey: CKRecordZone.default().zoneID)
			
			let recordServices = recordZoneDictionary.keys.map { AmazingZone(database: self.database,
																			 zoneID: $0) }
			let zoneNames = recordZoneDictionary.keys.map { $0.zoneName }
			
			var serviceForZoneName: [ZoneName: AmazingZone] = [:]
			
			for (index, element) in zoneNames.enumerated() {
				serviceForZoneName[element] = recordServices[index]
			}
			
			completion(.success(serviceForZoneName))
		}
		
		database.add(zoneCheckOperation)
	}
}
