namespace MikeNakis.Testing;

using MikeNakis.Kit;
using static MikeNakis.Kit.GlobalStatics;
using Sys = System;

public class FakeClock : Clock
{
	Sys.DateTime currentTime;
	public Sys.TimeZoneInfo TimeZone { get; set; }

	public FakeClock()
	{
		currentTime = new Sys.DateTime( 2020, 1, 1, 1, 0, 0 );
		Sys.TimeSpan timeSpan = new( -5, 0, 0 );
		string displayName = DotNetHelpers.MakeTimeZoneDisplayName( timeSpan );
		TimeZone = Sys.TimeZoneInfo.CreateCustomTimeZone( "Standard Testing Time", timeSpan, $"({displayName}) Testing Time (Testing Only)", "Standard Testing Time" );
	}

	public Sys.DateTime GetUniversalTime() => currentTime;
	public Sys.TimeZoneInfo GetLocalTimeZone() => TimeZone;

	public void SetCurrentTime( Sys.DateTime value )
	{
		Assert( value >= currentTime );
		currentTime = value;
	}
}
