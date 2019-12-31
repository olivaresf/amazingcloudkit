//
//  CKDatabaseCoordinator.swift
//  Amazing Humans
//
//  Created by Fernando Olivares on 12/17/19.
//  Copyright © 2019 Fernando Olivares. All rights reserved.
//

import Foundation
import CloudKit

public class CKDatabaseCoordinator {
	
	let type: DatabaseType
	public init(type: DatabaseType) {
		self.type = type
	}
	
	private func zoneID(shouldCreateZone: Bool = true) throws -> CKRecordZone.ID {
		
		switch type {
			
		case .app:
			return CKRecordZone.ID.default
		
		case .shared(let zoneName):
			guard let existingZone = try zoneExists(name: zoneName) else {
				if shouldCreateZone {
                    throw ZoneExistsError.zoneNotFoundAndCreationUnavailableInSharedDB
				} else {
					throw ZoneExistsError.zoneNotFoundAndNoCreationRequested
				}
			}
			
			return existingZone
			
		case .user(let possibleZoneName):
			
			guard let zoneName = possibleZoneName else { return CKRecordZone.ID.default }
			
			guard let existingZone = try zoneExists(name: zoneName) else {
				if shouldCreateZone {
					return try createZone(name: zoneName)
				} else {
					throw ZoneExistsError.zoneNotFoundAndNoCreationRequested
				}
			}
			
			return existingZone
		}
	}
}

// MARK: - Zones
public extension CKDatabaseCoordinator {
	
	func zoneExists(name zoneName: String) throws -> CKRecordZone.ID? {
        
		return try await { (awaitCompletion: @escaping (Result<CKRecordZone.ID?, ZoneExistsError>) -> Void) in
            
            let zoneCheckOperation = CKFetchRecordZonesOperation.fetchAllRecordZonesOperation()
            zoneCheckOperation.fetchRecordZonesCompletionBlock = { possibleRecordZonesDictionary, possibleError in
                
                guard possibleError == nil else {
                    awaitCompletion(.failure(.cloudKit(possibleError!)))
                    return
                }
                
                guard let recordZoneDictionary = possibleRecordZonesDictionary else {
                    awaitCompletion(.failure(.invalidStateNoZoneInformation))
                    return
                }
                
				awaitCompletion(.success(recordZoneDictionary.keys.filter({ $0.zoneName == zoneName }).first))
            }
            
			self.type.database.add(zoneCheckOperation)
        }
    }
	
	func createZone(name zoneName: String) throws -> CKRecordZone.ID {
        
        guard type != DatabaseType.shared(zoneName: zoneName) else {
            throw ZoneExistsError.zoneNotFoundAndCreationUnavailableInSharedDB
        }
        
        return try await { (awaitCompletion: @escaping (Result<CKRecordZone.ID, CreateZoneError>) -> Void) in
            
            let shareZoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
            let shareZone = CKRecordZone(zoneID: shareZoneID)
            let uploadZoneOperation = CKModifyRecordZonesOperation(recordZonesToSave: [shareZone], recordZoneIDsToDelete: nil)
            uploadZoneOperation.modifyRecordZonesCompletionBlock = { possibleSavedZones, _, possibleError in
                
                guard possibleError == nil else {
                    awaitCompletion(.failure(.cloudKit(possibleError!)))
                    return
                }
                
                guard let savedZones = possibleSavedZones else {
                    awaitCompletion(.failure(.invalidStateNoZonesReturned))
                    return
                }
                
                guard let index = savedZones.firstIndex(of: shareZone) else {
                    awaitCompletion(.failure(.invalidStateNoZoneCreated))
                    return
                }
                
                awaitCompletion(.success(savedZones[index].zoneID))
            }
            
			self.type.database.add(uploadZoneOperation)
        }
    }
}

// MARK: - Creating
public extension CKDatabaseCoordinator {
	
	func createRecord(recordType: String) throws -> CKRecord {
		let recordID = CKRecord.ID(recordName: UUID().uuidString, zoneID: try zoneID())
		return CKRecord(recordType: recordType, recordID: recordID)
	}
}

// MARK: - Fetching
public extension CKDatabaseCoordinator {
	
    func fetch(recordIDs: [CKRecord.ID], desiredKeys: [CKRecord.FieldKey]? = nil) throws -> SuccessfulFetch {
		
		guard !recordIDs.isEmpty else { return .fetch([]) }
		
		let currentZone = try zoneID()
		assert(recordIDs.reduce(true, { $0 && ($1.zoneID == currentZone) }), "Attempting to fetch objects in a record zone not in this coordinator")
		
		return try await { (awaitCompletion: @escaping (Result<SuccessfulFetch, FetchError>) -> Void) in
			
			let fetchOperation = CKFetchRecordsOperation(recordIDs: recordIDs)
            fetchOperation.desiredKeys = desiredKeys
            fetchOperation.qualityOfService = .userInitiated
			fetchOperation.fetchRecordsCompletionBlock = { possibleRecordsDictionary, possibleError in
				
				guard possibleError == nil else {
					awaitCompletion(.failure(.cloudKit(possibleError!)))
					return
				}
				
				guard let fetchedDictionary = possibleRecordsDictionary, !fetchedDictionary.isEmpty else {
					awaitCompletion(.failure(.invalidStateNoErrorButNoRecords))
					return
				}
				
				let fetchedRecords = fetchedDictionary.map { $0.value }
				
				guard fetchedRecords.count == recordIDs.count else {
					awaitCompletion(.success(.partial(fetchedRecords)))
					return
				}
				
				awaitCompletion(.success(.fetch(fetchedRecords)))
			}
			
			self.type.database.add(fetchOperation)
		}
	}
	
	func fetchRecords(recordType: String, predicate: NSPredicate = NSPredicate(value: true)) throws -> [CKRecord] {
		
		let currentZoneID = try self.zoneID()
		return try await { (awaitCompletion: @escaping (Result<[CKRecord], FetchError>) -> Void) in
			
			let query = CKQuery(recordType: recordType, predicate: predicate)
            let fetchRecordOperation = CKQueryOperation(query: query)
            fetchRecordOperation.qualityOfService = .userInitiated
            fetchRecordOperation.zoneID = currentZoneID
            
            var records = [CKRecord?]()
            fetchRecordOperation.recordFetchedBlock = {
                records.append($0)
            }
            
            fetchRecordOperation.queryCompletionBlock = { _, error in
                
                guard error == nil else {
                    awaitCompletion(.failure(.cloudKit(error!)))
                    return
                }
                
                awaitCompletion(.success(records.compactMap({ $0 })))
            }
            
            self.type.database.add(fetchRecordOperation)
		}
    }
}

// MARK: - Saving
public extension CKDatabaseCoordinator {
	
	func save(record: CKRecord) throws -> CKRecord {
		
		let savedRecords = try save(records: [record])
		
		guard !savedRecords.isEmpty, let newRecord = savedRecords.first else {
			throw SaveError.invalidStateNoErrorButNoRecordEither
		}
		
		return newRecord
	}
	
	func save(records: [CKRecord]) throws -> [CKRecord] {
		
		guard !records.isEmpty else { return [] }
		
		let currentZoneID = try zoneID()
		assert(records.reduce(true, { $0 && ($1.recordID.zoneID == currentZoneID) }), "Attempting to save objects in a record zone not in this coordinator")
		
        return try await { (awaitCompletion: @escaping (Result<[CKRecord], SaveError>) -> Void) in
            
            let makeURLPublicOperation = CKModifyRecordsOperation(recordsToSave: records, recordIDsToDelete: nil)
            makeURLPublicOperation.qualityOfService = .userInitiated
            makeURLPublicOperation.modifyRecordsCompletionBlock = { possiblePublicInvites, _, possiblePublicInvitesError in
                
                guard possiblePublicInvitesError == nil else {
                    awaitCompletion(.failure(.cloudKit(possiblePublicInvitesError!)))
                    return
                }
                
                guard let publicInvites = possiblePublicInvites else {
                    awaitCompletion(.failure(.invalidStateNoErrorButNoRecordEither))
                    return
                }
                
                awaitCompletion(.success(publicInvites))
            }
            
			self.type.database.add(makeURLPublicOperation)
        }
    }
}


// MARK: - Subscriptions
public extension CKDatabaseCoordinator {
	
	func subscriptions() throws -> [CKSubscription] {
        
        return try await { (awaitCompletion: @escaping (Result<[CKSubscription], FetchError>) -> Void) in
            
			self.type.database.fetchAllSubscriptions { possibleSubscriptions, possibleError in
                       
                // Check if we succeeded.
                guard possibleError == nil else {
                    awaitCompletion(.failure(.cloudKit(possibleError!)))
                    return
                }
                
                // We succeeded. Any subscriptions found?
                guard let subscriptions = possibleSubscriptions else {
                    awaitCompletion(.failure(.invalidStateNoErrorButNoRecords))
                    return
                }
                
                awaitCompletion(.success(subscriptions))
            }
        }
    }
}

// MARK: - Enums
public extension CKDatabaseCoordinator {
	
    enum DatabaseType : Equatable {
		case user(possibleZoneName: String?)
		case shared(zoneName: String)
		case app
		
		var database: CKDatabase {
			switch self {
			case .user: return CKContainer.default().privateCloudDatabase
			case .shared: return CKContainer.default().sharedCloudDatabase
			case .app: return CKContainer.default().publicCloudDatabase
			}
		}
	}
	
	enum SuccessfulFetch {
		case partial([CKRecord])
		case fetch([CKRecord])
		
		public var records: [CKRecord] {
			switch self {
			case .fetch(let records), .partial(let records):
				return records
			}
		}
	}
	
	enum FetchError : Error {
		case cloudKit(Error)
		case invalidStateNoErrorButNoRecords
		case unknown(Error)
	}
    enum ZoneExistsError : Error {
		case cloudKit(Error)
        case invalidStateNoZoneInformation
		case invalidStateZoneFoundButNoIDAssociated
		case zoneNotFoundAndNoCreationRequested
        case zoneNotFoundAndCreationUnavailableInSharedDB
    }
	enum CreateZoneError: Error {
        case cloudKit(Error)
        case invalidStateNoZonesReturned
        case invalidStateNoZoneCreated
    }
	enum SaveError : LocalizedError {
	case cloudKit(Error)
	case invalidStateNoErrorButNoRecordEither
	case invalidStateSavedRecordIsCorrupt
	case invalidStatePartialSave
	case unknown(Error)
	}
}
