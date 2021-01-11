//
//  AllAppUsersDatabase.swift
//  AmazingCloudKit
//
//  Created by Fernando Olivares on 24/04/20.
//  Copyright © 2020 Fernando Olivares. All rights reserved.
//

import Foundation
import CloudKit

public class AllAppUsersDatabase {
	
	/// All users of your app, regardless of authentication state, may read from this database.
	public let read: ReadableZone
	
	/// Only authenticated users may write.
	/// In order to initialize this service, call AmazingCloudkit's `resolveUser`.
	public internal(set) var write: WritableZone?
	
	public let subscriptions: SubscriptionService
	
	init(container: CKContainer) {
		read = ReadableZone(database: container.publicCloudDatabase,
							zoneID: CKRecordZone.default().zoneID)
		
		subscriptions = SubscriptionService(container: container,
											database: container.publicCloudDatabase)
	}
}
