//
//  ReadableZone.swift
//  AmazingCloudKit
//
//  Created by Fernando Olivares on 10/05/20.
//  Copyright © 2020 Fernando Olivares. All rights reserved.
//

import Foundation
import CloudKit

/// Responsible for fetching records from a single zone.
public class ReadableZone {
	
	private let zoneID: CKRecordZone.ID
	private let database: CKDatabase
	init(database: CKDatabase, zoneID: CKRecordZone.ID) {
		self.database = database
		self.zoneID = zoneID
	}
}

/// MARK: - Fetch CKRecordConvertible
extension ReadableZone {
	
	/// Checks ownership of a CKRecord
	///
	/// - Parameter record: the record to be checked
	/// - Returns: true if the record's `existingRecord` is held by this object's zoneID.
	public func owns<RecordType: CKRecordDecodable>(_ recordConvertible: RecordType) -> Bool {
		
		guard let backingRecord = recordConvertible.saveState.backingRecord else {
			return false
		}
		
		return backingRecord.recordID.zoneID == zoneID
	}
	
	/// As per the documentation of `CKQueryOperation`, queries are restricted to the records in a single zone.
	///
	/// - Parameters:
	///   - predicate: if no predicate, returns all the records of type `RecordType`
	///   - completion: self-explanatory
	public func fetch<RecordType: CKRecordDecodable & CKRecordIdentifiable>(predicate: NSPredicate = NSPredicate(value: true),
																			completion: @escaping (Result<[RecordType], Error>) -> Void) {
		
		fetchPartialRecords(predicate: predicate, recordType: RecordType.recordType) { result in
			
			// CKRecord -> RecordType
			let mappedResult = result.map { fetchedRecords -> [RecordType] in
				
				let mappedRecords = fetchedRecords.map { record -> RecordType in
					var mappedRecord = RecordType(cloudKitRecord: record)
					mappedRecord.saveState = .saved(backingRecord: record,
													zoneName: self.zoneID.zoneName)
					return mappedRecord
				}
				
				return mappedRecords
			}
			
			completion(mappedResult)
		}
	}
	
	public func fetch<RecordType: CKRecordDecodable & CKRecordIdentifiable>(recordIDs: [CKRecord.ID],
																			completion: @escaping (Result<SuccessfulFetch<RecordType>, AmazingCloudKit.FetchError>) -> Void) {
		
		fetchPartialRecords(recordIDs: recordIDs, recordType: RecordType.recordType) { result in
			
			let mappedResult = result.map { fetchedDictionary -> SuccessfulFetch<RecordType> in
				
				// CKRecord -> RecordType
				let fetchedRecords = fetchedDictionary
					.map { keyValuePair -> RecordType in
						var mappedRecord = RecordType(cloudKitRecord: keyValuePair.value)
						mappedRecord.saveState = .saved(backingRecord: keyValuePair.value,
														zoneName: self.zoneID.zoneName)
						return mappedRecord
				}
				
				
				guard fetchedRecords.count == recordIDs.count else {
					return .partial(fetchedRecords)
				}
				
				return .fetch(fetchedRecords)
			}
			
			completion(mappedResult)
		}
	}
	
	/// Fetch all records from single record type across all zones.
	///
	/// - Parameters:
	///   - customZones: if nil, fails
	///   - predicate: self-explanatory
	///   - completion: self-explanatory
	static func fetch<RecordType: CKRecordDecodable & CKRecordIdentifiable>(customZones: [ZoneName : AmazingZone]?,
																			predicate: NSPredicate = NSPredicate(value: true),
																			completion: @escaping (Result<[Result<[RecordType], Error>], ResolveCustomZonesError>) -> Void) {
		
		// Result<[Result<[CKRecord], Error>], Error> -> Result<Result<[RecordType], Error>, Error>
		fetchAllPartialRecords(customZones: customZones, predicate: predicate, recordType: RecordType.recordType) { allZonesCKResult in
			
			// [Result<[CKRecord], Error>] -> [Result<[RecordType], Error>]
			let allZonesRecordTypeResult = allZonesCKResult.map { allZonesCKSuccess -> [Result<[RecordType], Error>] in
				
				// Result<[CKRecord], Error> -> Result<[RecordType], Error>
				let allZonesRecordTypeSuccess = allZonesCKSuccess.map { singleZoneCKSuccess -> Result<[RecordType], Error> in
					
					// [CKRecord] -> [RecordType]
					let singleZoneRecordTypeSuccess = singleZoneCKSuccess.map { singleZoneCKRecords -> [RecordType] in
						
						// CKRecord -> RecordType
						let singleZoneRecordTypes = singleZoneCKRecords.map { singleCKRecord -> RecordType in
							var mappedRecord = RecordType(cloudKitRecord: singleCKRecord)
							mappedRecord.saveState = .saved(backingRecord: singleCKRecord,
															zoneName: singleCKRecord.recordID.zoneID.zoneName)
							return mappedRecord
						}
						
						return singleZoneRecordTypes
					}
					
					return singleZoneRecordTypeSuccess
				}
				
				return allZonesRecordTypeSuccess
			}
			
			completion(allZonesRecordTypeResult)
		}
	}
}

/// MARK: - Fetch CKRecord
extension ReadableZone {
	
	/// Since fetching a partial record may not yield a full `CKRecordConvertible`, we return CKRecords.
	/// Even if `desiredKeys` is nil, no transformation happens. If you want your records to be immediately transformed, use `fetch`.
	///
	/// - Parameters:
	///   - predicate: if no predicate, returns all the records of type `RecordType`
	///   - completion: self-explanatory
	public func fetchPartialRecords(predicate: NSPredicate = NSPredicate(value: true),
									desiredKeys: [CKRecord.FieldKey]? = nil,
									recordType: String,
									completion: @escaping (Result<[CKRecord], Error>) -> Void) {
		
		let query = CKQuery(recordType: recordType, predicate: predicate)
		let fetchRecordOperation = CKQueryOperation(query: query)
		fetchRecordOperation.qualityOfService = .userInitiated
		fetchRecordOperation.zoneID = zoneID
		fetchRecordOperation.desiredKeys = desiredKeys
		
		var records = [CKRecord]()
		fetchRecordOperation.recordFetchedBlock = {
			records.append($0)
		}
		
		fetchRecordOperation.queryCompletionBlock = { _, possibleError in
			
			guard possibleError == nil else {
				completion(.failure(possibleError!))
				return
			}
			
			completion(.success(records))
		}
		
		database.add(fetchRecordOperation)
	}
	
	/// Since fetching a partial record may not yield a full `CKRecordConvertible`, we return CKRecords.
	/// Even if `desiredKeys` is nil, no transformation happens. If you want your records to be immediately transformed, use `fetch`.
	///
	/// - Parameters:
	///   - recordIDs: ids to fetch
	///   - desiredKeys: only these keys will be populated
	///   - recordType: self-explanatory
	///   - completion: self-explanatory
	public func fetchPartialRecords(recordIDs: [CKRecord.ID],
									desiredKeys: [CKRecord.FieldKey]? = nil,
									recordType: String,
									completion: @escaping (Result<[CKRecord.ID : CKRecord], AmazingCloudKit.FetchError>) -> Void) {
		
		guard !recordIDs.isEmpty else {
			completion(.success([:]))
			return
		}
		
		let fetchOperation = CKFetchRecordsOperation(recordIDs: recordIDs)
		fetchOperation.desiredKeys = desiredKeys
		fetchOperation.qualityOfService = .userInitiated
		fetchOperation.fetchRecordsCompletionBlock = { possibleRecordsDictionary, possibleError in
			guard possibleError == nil else {
				completion(.failure(.cloudKit(possibleError!)))
				return
			}
			
			guard let fetchedDictionary = possibleRecordsDictionary, !fetchedDictionary.isEmpty else {
				completion(.failure(.invalidStateNoErrorButNoRecords))
				return
			}
			
			completion(.success(fetchedDictionary))
		}
		database.add(fetchOperation)
	}
	
	/// Fetch all records from single record type across all zones.
	/// Since fetching a partial record may not yield a full `CKRecordConvertible`, we return CKRecords.
	/// Even if `desiredKeys` is nil, no transformation happens. If you want your records to be immediately transformed, use `fetch`.
	///
	/// - Parameters:
	///   - customZones: if nil, fails
	///   - predicate: self-explanatory
	///   - completion: self-explanatory
	static func fetchAllPartialRecords(customZones: [ZoneName : AmazingZone]?,
									   predicate: NSPredicate = NSPredicate(value: true),
									   desiredKeys: [CKRecord.FieldKey]? = nil,
									   recordType: String,
									   completion: @escaping (Result<[Result<[CKRecord], Error>], ResolveCustomZonesError>) -> Void) {
		
		guard let existingZones = customZones else {
			completion(.failure(.emptyZones))
			return
		}
		
		precondition(existingZones.count > 0, "Invalid state: customZones is non-nil and empty")
		
		let fetchRecordsDispatchGroup = DispatchGroup()
		var allResults: [Result<[CKRecord], Error>] = []
		
		existingZones.forEach { (zoneName, service) in
			fetchRecordsDispatchGroup.enter()
			service.read.fetchPartialRecords(predicate: predicate, desiredKeys: desiredKeys, recordType: recordType) { result in
				allResults.append(result)
				fetchRecordsDispatchGroup.leave()
			}
		}
		
		fetchRecordsDispatchGroup.notify(queue: DispatchQueue.global()) {
			completion(.success(allResults))
		}
	}
	
}

extension ReadableZone {
	
	public enum SuccessfulFetch<RecordType: CKRecordConvertible> {
		case partial([RecordType])
		case fetch([RecordType])
		public var records: [RecordType] {
			switch self {
			case .fetch(let records), .partial(let records):
				return records
			}
		}
	}
	
	public enum ResolveCustomZonesError : Error {
		case emptyZones
	}
}

extension ReadableZone : Equatable {
	public static func == (lhs: ReadableZone, rhs: ReadableZone) -> Bool {
		return lhs.zoneID == rhs.zoneID && lhs.database == rhs.database
	}
}
