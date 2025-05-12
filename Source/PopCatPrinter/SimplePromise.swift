import Combine


public class PromiseWrapper<ResolvedValue>
{
	var future : Future<ResolvedValue,any Error>!
	private var resolvingFunctor : ((Result<ResolvedValue,any Error>)->Void)!
	
	//public init(resolvingFunctor:@escaping (Result<ResolvedValue,any Error>)->Void)
	public init()
	{
		let future = Future<ResolvedValue,any Error>()
		{
			promise in
			self.resolvingFunctor = promise
		}
		self.future = future
	}
	
	public func Resolve(_ data:ResolvedValue)
	{
		resolvingFunctor( Result.success(data) )
	}
	
	public func Reject(_ error:Error)
	{
		resolvingFunctor( Result.failure(error) )
	}
	
	public func Wait() async throws -> ResolvedValue
	{
		try await self.future.value
	}
}
