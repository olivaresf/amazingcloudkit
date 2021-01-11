//
//  FriendsDatabase.swift
//  AmazingCloudKit
//
//  Created by Fernando Olivares on 24/04/20.
//  Copyright © 2020 Fernando Olivares. All rights reserved.
//

import Foundation
import CloudKit

public class FriendsDatabase {
	
	// If the database exists, this is guaranteed to be non-nil.
	public let customZones: [ZoneName: AmazingZone]
	
	public let subscriptions: SubscriptionService
	
	init?(container: CKContainer, customZones: [ZoneName: AmazingZone]) {
		
		guard !customZones.isEmpty else { return nil }
		
		self.customZones = customZones
		subscriptions = SubscriptionService(container: container,
											database: container.sharedCloudDatabase)
	}
	
	#warning("We need to change the name to something like `fetchAll`, but we aren't yet fetching from the default zone.")
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
	public func fetch<RecordType: CKRecordConvertible>(predicate: NSPredicate = NSPredicate(value: true),
													   completion: @escaping (Result<[Result<[RecordType], Error>], ReadableZone.ResolveCustomZonesError>) -> Void) {
		ReadableZone.fetch(customZones: customZones) {
			completion($0)
		}
	}
}
