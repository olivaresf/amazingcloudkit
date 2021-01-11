//
//  DBProvider.swift
//  AmazingCloudKit
//
//  Created by Fernando Olivares on 18/04/20.
//  Copyright © 2020 Fernando Olivares. All rights reserved.
//

import Foundation
import CloudKit

protocol MultipleZoneProvider {
	
	var otherResolvedZones: [CKRecordZone.ID]! { get }
	
	func createRecord(_ recordType: String, zoneName: String) -> Result<CKRecord, ZoneExistsError>
}

public class SingleZoneProvider {
	
	var container: CKContainer {
		return privateContainer
	}
	
	var database: CKDatabase {
		fatalError("Should be implemented by subclasses")
	}
	
	private var resolvedZone: CKRecordZone.ID!
	
	private let privateContainer: CKContainer
	required init(container: CKContainer) {
		privateContainer = container
	}
	
	/// Succeeds if _at least_ one zone exists.
	/// If at least one zone exists, the first zone returned will be saved in `resolvedZone`.
	/// If more than one zone exist, additional zones are returned via the completion block.
	///
	/// - Parameter additionalZones: zones remaining after saving the first returned zone in resolvedZone.
	func resolveZone(_ additionalZones: @escaping (Result<[CKRecordZone.ID], ZoneExistsError>) -> Void) {
		
		// If we already resolved, we're done.
		guard resolvedZone == nil else {
			additionalZones(.success([]))
			return
		}
		
		fetchZones { result in
			switch result {
				
			case .success(var resolvedZones):
				
				guard !resolvedZones.isEmpty else {
					additionalZones(.failure(.zoneNotFound))
					return
				}
				
				self.resolvedZone = resolvedZones.removeFirst()
				self.resolveRemaining(zones: resolvedZones)
				additionalZones(.success([]))
				
			case .failure(let error):
				additionalZones(.failure(error))
			}
		}
	}
	
	func resolveRemaining(zones: [CKRecordZone.ID]) {
		// Intentionally left blank since Public and some Private dbs do not have additional zones to resolve.
	}
}

// MARK: - Creating
extension SingleZoneProvider {
	
	func fetchZones(_ completion: @escaping (Result<[CKRecordZone.ID], ZoneExistsError>) -> Void) {
		
		let zoneCheckOperation = CKFetchRecordZonesOperation.fetchAllRecordZonesOperation()
		zoneCheckOperation.fetchRecordZonesCompletionBlock = { possibleRecordZonesDictionary, possibleError in
			
			guard possibleError == nil else {
				completion(.failure(.cloudKit(possibleError!)))
				return
			}
			
			guard let recordZoneDictionary = possibleRecordZonesDictionary else {
				completion(.failure(.invalidStateNoZoneInformation))
				return
			}
			
			let allRecordIDs = Array(recordZoneDictionary.keys)
			completion(.success(allRecordIDs))
		}
		
		database.add(zoneCheckOperation)
	}
}

// MARK: - Creating

private func createRecord(_ recordType: String, zoneID: CKRecordZone.ID) -> Result<CKRecord, ZoneExistsError> {
	let recordID = CKRecord.ID(recordName: UUID().uuidString, zoneID: zoneID)
	return .success(CKRecord(recordType: recordType, recordID: recordID))
}

extension SingleZoneProvider {
	func createRecord(_ recordType: String) -> Result<CKRecord, ZoneExistsError> {
		return createRecord(recordType, zoneID: resolvedZone)
	}
}

extension MultipleZoneProvider {
	func createRecord(_ recordType: String, zoneName: String) -> Result<CKRecord, ZoneExistsError> {
		
		guard let foundZone = otherResolvedZones
			.filter({ $0.zoneName == zoneName })
			.first else {
				return .failure(.zoneNotFound)
		}
		
		return createRecord(recordType, zoneID: foundZone)
	}
}
