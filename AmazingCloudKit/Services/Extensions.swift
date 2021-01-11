//
//  Extensions.swift
//  AmazingCloudKit
//
//  Created by Fernando Olivares on 18/05/20.
//  Copyright © 2020 Fernando Olivares. All rights reserved.
//

import Foundation

extension Optional {
	
	enum UnwrapError<Wrapped>: Error {
		case nilValue(_ wrapped: Wrapped.Type)
	}
	
	func unwrap() throws -> Wrapped {
		
		guard case .some(let value) = self else {
			throw UnwrapError.nilValue(Wrapped.self)
		}
		
		return value
	}
}
