
public extension Task where Success == Never, Failure == Never
{
	internal static func sleep(milliseconds: Int) async
	{
		let Nanos = UInt64(milliseconds * 1_000_000)
		do
		{
			try await Task.sleep(nanoseconds: Nanos)
		}
		catch
		{
		}
	}
}
