//
//  SubscriptionProvider.swift
//  AmazingCloudKit
//
//  Created by Fernando Olivares on 24/04/20.
//  Copyright © 2020 Fernando Olivares. All rights reserved.
//

import Foundation
import CloudKit

public class SubscriptionService {
	
	private let container: CKContainer
	private let database: CKDatabase
	init(container: CKContainer, database: CKDatabase) {
		self.container = container
		self.database = database
	}
	
	public enum RegisterForInviteNotificationsError: Error {
		case shouldRequestPermissionFirst
		case subscription(Error)
		case saveSucceededButNoSubscriptionsWereReturned
		case savingSubscription(Error)
		case invalidStateNoSubscription
	}
	
	public func subscribe(_ subscription: CKSubscription,
						  completion: @escaping (Result<Bool, RegisterForInviteNotificationsError>) -> Void) {
		
		self.database.save(subscription) { (possibleSubscription, possibleError) in
			
			guard possibleError == nil else {
				// Code 15 means the user already has a CKSubscription identical to `subscription` in the database.
				guard (possibleError as! CKError).code.rawValue != 15 else {
					completion(.success(false))
					return
				}
				
				completion(.failure(.savingSubscription(possibleError!)))
				return
			}
			
			guard possibleSubscription != nil else {
				completion(.failure(.invalidStateNoSubscription))
				return
			}
			
			completion(.success(true))
		}
		
	}
	
	public func fetch(completion: @escaping (Result<[CKSubscription], AmazingCloudKit.FetchError>) -> Void) {
		
		database.fetchAllSubscriptions { possibleSubscriptions, possibleError in
			
			// Check if we succeeded.
			guard possibleError == nil else {
				completion(.failure(.cloudKit(possibleError!)))
				return
			}
			
			// We succeeded. Any subscriptions found?
			guard let subscriptions = possibleSubscriptions else {
				completion(.failure(.invalidStateNoErrorButNoRecords))
				return
			}
			
			completion(.success(subscriptions))
		}
	}
}

