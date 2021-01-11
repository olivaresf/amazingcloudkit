//
//  AuthenticatedUserDatabase.swift
//  AmazingCloudKit
//
//  Created by Fernando Olivares on 24/04/20.
//  Copyright © 2020 Fernando Olivares. All rights reserved.
//

import Foundation
import CloudKit

public class AuthenticatedUserDatabase {
	
	// Authenticated users will always have read/write access to their own database via a default zone.
	public let read: ReadableZone
	public let write: WritableZone
	
	// You only get access to custom zones if the authenticated user has created them.
	// In order to initialize this variable, call `resolveCustomZones`.
	//
	// If non-nil, it is guaranteed to not be empty.
	public private(set) var customZones: [ZoneName: AmazingZone]? = nil
	
	public let subscriptions: SubscriptionService
	
	init(container: CKContainer) {
		self.container = container
		
		read = ReadableZone(database: container.privateCloudDatabase,
							zoneID: CKRecordZone.default().zoneID)
		write = WritableZone(database: container.privateCloudDatabase,
							 zoneID: CKRecordZone.default().zoneID)
		
		customZoneCreator = CustomZoneCreator(container: container)
		customZoneFetcher = CustomZoneFetcher(database: container.privateCloudDatabase)
		subscriptions = SubscriptionService(container: container,
											database: container.privateCloudDatabase)
	}
	
	private let customZoneCreator: CustomZoneCreator
	private let customZoneFetcher: CustomZoneFetcher
	
	private let container: CKContainer
}

extension AuthenticatedUserDatabase {
	
	/// Fetch a single record type from across all zones.
	/// As per documentation, one fetch request per zone will be used, so this may be a long running function, depending on network.
	///
	/// Will fail only if `customZones` is nil. If `customZones` is non-nil, you are guaranteed to be returned a success. However, that success holds individual requests' results, so you are not guaranteed any data.
	///
	/// e.g. if zone 3 out of 5 fails, the resulting array will contain a `.failure(error)` at index 2.
	///
	/// - Parameters:
	///   - predicate: self-explanatory
	///   - completion: if successful, an array of individual fetch request results
	func fetch<RecordType: CKRecordConvertible>(predicate: NSPredicate = NSPredicate(value: true),
												completion: @escaping (Result<[Result<[RecordType], Error>], ReadableZone.ResolveCustomZonesError>) -> Void) {
		ReadableZone.fetch(customZones: customZones) {
			completion($0)
		}
	}
}

extension AuthenticatedUserDatabase {
	/// Attempts to initialize `customZones` by fetching all zones in the private database.
	///
	/// If successful, `[ZoneName: RecordService]` is guaranteed to not be empty.
	///
	/// - Parameter completion: self-explaantory
	public func resolveCustomZones(completion: @escaping (Result<[ZoneName: AmazingZone], ZoneExistsError>) -> Void) {
		
		customZoneFetcher.fetch { result in
			switch result {
				
			case .success(let resolvedZones):
				
				guard resolvedZones.count > 0 else {
					self.customZones = nil
					completion(.failure(.invalidStateNoZonesReturned))
					return
				}
				
				self.customZones = resolvedZones
				completion(.success(resolvedZones))
				
			case .failure(let error):
				self.customZones = nil
				completion(.failure(error))
			}
		}
	}
	
	/// If successful, the new zone gets added to `customZones: [ZoneName: RecordService]`.
	///
	/// - Parameters:
	///   - zoneName: self-explanatory
	///   - completion: self-explanatory
	public func newCustomZone(_ zoneName: ZoneName? = nil,
							  completion: @escaping (Result<AmazingZone, CustomZoneCreator.CreateZoneError>) -> Void) {
		
		let givenZoneName = zoneName ?? UUID().uuidString
		
		customZoneCreator.create(givenZoneName) { result in
			switch result {
				
			case .success(let newZoneID):
				let newRecordServiceForZoneID = AmazingZone(database: self.container.privateCloudDatabase,
															zoneID: newZoneID)
				
				if var existingCustomZones = self.customZones {
					existingCustomZones[newZoneID.zoneName] = newRecordServiceForZoneID
					self.customZones = existingCustomZones
				} else {
					self.customZones = [newZoneID.zoneName: newRecordServiceForZoneID]
				}
				
				completion(.success(newRecordServiceForZoneID))
				
			case .failure(let error):
				completion(.failure(error))
				
			}
		}
	}
}
