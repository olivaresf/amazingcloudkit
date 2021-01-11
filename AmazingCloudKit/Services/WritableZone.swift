//
//  WritableZone.swift
//  AmazingCloudKit
//
//  Created by Fernando Olivares on 10/05/20.
//  Copyright © 2020 Fernando Olivares. All rights reserved.
//

import Foundation
import CloudKit

/// Responsible for writing records to a single zone.
public class WritableZone {
	
	let zoneID: CKRecordZone.ID
	let database: CKDatabase
	init(database: CKDatabase, zoneID: CKRecordZone.ID) {
		self.database = database
		self.zoneID = zoneID
	}
}

extension WritableZone {
	
	public func newUnsavedRecordID(named: String) -> CKRecord.ID {
		return CKRecord.ID(recordName: named, zoneID: zoneID)
	}
	
	public func newUnsavedRecord(named: String, type: String) -> CKRecord {
		let recordID = CKRecord.ID(recordName: named, zoneID: zoneID)
		return CKRecord(recordType: type, recordID: recordID)
	}
}

extension WritableZone {
	
	public enum SaveError : Error {
		case zonesDoNotBelongToProvider([CKRecordZone.ID])
		case cloudKit(Error)
		case invalidStateNoErrorButNoRecordEither
		case invalidStateSavedRecordIsCorrupt
		case invalidStatePartialSave
		case objectShouldBeCreatedUsingProvider
	}
	
	public func save<RecordType: CKRecordConvertible>(_ recordConvertible: RecordType,
													  zoneName: ZoneName? = nil,
													  completion: @escaping (Result<RecordType, SaveError>)-> Void) {
		
		save(changes: .modifyOrCreate([recordConvertible])) { (saveResult: Result<Changes<RecordType>, SaveError>) in
			
			switch saveResult {
				
			case .success(let savedChanges):
				
				guard case .modifyOrCreate(let savedRecords) = savedChanges else {
					assertionFailure("`save<RecordType> is only for adding records`")
					completion(.failure(.invalidStateSavedRecordIsCorrupt))
					return
				}
				
				guard !savedRecords.isEmpty, let newRecord = savedRecords.first else {
					completion(.failure(.invalidStateNoErrorButNoRecordEither))
					return
				}
				
				completion(.success(newRecord))
				
			case .failure(let saveError):
				completion(.failure(saveError))
			}
			
		}
	}
	
	public enum Changes<RecordType: CKRecordConvertible> {
		case modifyOrCreate([RecordType])
		case delete([CKRecord.ID])
		case multiple(modifyOrCreate: [RecordType], delete: [CKRecord.ID])
		
		public var modified: [RecordType] {
			switch self {
			case .modifyOrCreate(let recordTypeArray):
				return recordTypeArray
				
			case .delete:
				return []
				
			case .multiple(let modifyOrCreate, _):
				return modifyOrCreate
			}
		}
		
		public var deleted: [CKRecord.ID] {
			switch self {
			case .modifyOrCreate:
				return []
				
			case .delete(let recordIDs):
				return recordIDs
				
			case .multiple(_, let recordIDs):
				return recordIDs
			}
		}
	}
	
	public func save<RecordType: CKRecordConvertible>(changes: Changes<RecordType>,
													  completion: @escaping (Result<Changes<RecordType>, SaveError>)-> Void) {
		
		#warning("We need to think what to do if some records are filtered here.")
		let recordsToModifyInThisZone = changes.modified
			// `RecordType: CKRecordConvertible` -> `CKRecord`
			.compactMap { recordConvertible -> CKRecord? in
				
				// If we're overwriting, we're done.
				switch recordConvertible.saveState {
				case .local:
					// This is a new record.
					let recordID = CKRecord.ID(recordName: UUID().uuidString, zoneID: self.zoneID)
					let record = CKRecord(recordType: RecordType.recordType, recordID: recordID)
					recordConvertible.convert(to: record)
					return record
					
				case .saved(let backingRecord, let zoneName),
					 .unsaved(let backingRecord, let zoneName):
					
					guard zoneName == self.zoneID.zoneName else { return nil }
					
					return backingRecord
					
				}
		}
		
		let recordIDsToDeleteInThisZone = changes.deleted
			.filter { $0.zoneID == zoneID }
		
		let recordChanges: PartialChanges
		
		switch changes {
		case .modifyOrCreate:
			recordChanges = .modifyOrCreate(recordsToModifyInThisZone)
			
		case .delete:
			recordChanges = .delete(recordIDsToDeleteInThisZone)
			
		case .multiple:
			recordChanges = .multiple(modifyOrCreate: recordsToModifyInThisZone,
									  delete: recordIDsToDeleteInThisZone)
		}
		
		save(records: recordChanges) { result in
			
			switch result {
			case .success(let savedChanges):
				
				switch savedChanges {
					
				case .modifyOrCreate(let savedRecords):
					let mappedRecords = savedRecords.map { record -> RecordType in
						var mappedRecord = RecordType(cloudKitRecord: record)
						mappedRecord.saveState = .saved(backingRecord: record,
														zoneName: self.zoneID.zoneName)
						return mappedRecord
					}
					
					completion(.success(.modifyOrCreate(mappedRecords)))
					
				case .delete(let deletedRecordIDs):
					completion(.success(.delete(deletedRecordIDs)))
					
				case .multiple(let savedRecords, let deletedRecordIDs):
					let mappedRecords = savedRecords.map { record -> RecordType in
						var mappedRecord = RecordType(cloudKitRecord: record)
						mappedRecord.saveState = .saved(backingRecord: record,
														zoneName: self.zoneID.zoneName)
						return mappedRecord
					}
					
					completion(.success(.multiple(modifyOrCreate: mappedRecords,
												  delete: deletedRecordIDs)))
				}
				
			case .failure(let error):
				completion(.failure(error))
			}
			
		}
		
	}
	
	public enum PartialChanges {
		case modifyOrCreate([CKRecord])
		case delete([CKRecord.ID])
		case multiple(modifyOrCreate: [CKRecord], delete: [CKRecord.ID])
		
		public var modified: [CKRecord] {
			switch self {
			case .modifyOrCreate(let recordTypeArray):
				return recordTypeArray
				
			case .delete:
				return []
				
			case .multiple(let modifyOrCreate, _):
				return modifyOrCreate
			}
		}
		
		public var deleted: [CKRecord.ID] {
			switch self {
			case .modifyOrCreate:
				return []
				
			case .delete(let recordIDs):
				return recordIDs
				
			case .multiple(_, let recordIDs):
				return recordIDs
			}
		}
	}
	
	public func save(records changes: PartialChanges,
					 completion: @escaping (Result<PartialChanges, SaveError>)-> Void) {
		
		var addedOrModified = [CKRecord]()
		var deleted = [CKRecord.ID]()
		switch changes {
		case .delete(let recordsToDelete):
			deleted = recordsToDelete
			
		case .modifyOrCreate(let recordsToCreateOrModify):
			addedOrModified = recordsToCreateOrModify
			
		case .multiple(let recordsToCreateOrModify, let recordsToDelete):
			deleted = recordsToDelete
			addedOrModified = recordsToCreateOrModify
		}
		
		let saveChangesOperation = CKModifyRecordsOperation(recordsToSave: addedOrModified,
															recordIDsToDelete: deleted)
		saveChangesOperation.qualityOfService = .userInitiated
		saveChangesOperation.modifyRecordsCompletionBlock = { possibleSavedRecords, possibleErasedRecords, possibleError in
			
			guard possibleError == nil else {
				completion(.failure(.cloudKit(possibleError!)))
				return
			}
			
			let createdOrModifiedRecords = possibleSavedRecords ?? []
			let deletedRecords = possibleErasedRecords ?? []
			switch changes {
			case .delete:
				completion(.success(.delete(deletedRecords)))
				
			case .modifyOrCreate:
				completion(.success(.modifyOrCreate(createdOrModifiedRecords)))
				
			case .multiple:
				completion(.success(.multiple(modifyOrCreate: createdOrModifiedRecords,
											  delete: deletedRecords)))
			}
		}
		
		database.add(saveChangesOperation)
	}
}

extension WritableZone : Equatable {
	public static func == (lhs: WritableZone, rhs: WritableZone) -> Bool {
		return lhs.zoneID == rhs.zoneID && lhs.database == rhs.database
	}
}
