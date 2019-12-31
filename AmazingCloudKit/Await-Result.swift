//
//  Await-Result.swift
//  Amazing Humans
//
//  Created by Fernando Olivares on 11/24/19.
//  Copyright © 2019 Fernando Olivares. All rights reserved.

import Foundation

enum AwaitError : Error {
	case timeOut(identifier: String)
}

typealias AsyncExecutionCompletedBlock<T, U: Error> = (Result<T, U>) -> Void

func await<T, U: Error>(identifier: String? = nil, timeout: DispatchTime? = nil, asyncExecutionBlock: @escaping (@escaping AsyncExecutionCompletedBlock<T, U>) -> Void) throws -> T {
	
	let semaphore = DispatchSemaphore(value: 0)
	var possibleSuccess: T? = nil
	var possibleError: U? = nil
	
	asyncExecutionBlock { result in
		switch result {
		case .success(let success): possibleSuccess = success
		case .failure(let error): possibleError = error
		}
		semaphore.signal()
	}
	
	let _ = semaphore.wait(timeout: timeout ?? .distantFuture)
	guard possibleError == nil else {
		throw possibleError!
	}
	
	guard let success = possibleSuccess else {
		throw AwaitError.timeOut(identifier: UUID().uuidString)
	}
	
	return success
}
