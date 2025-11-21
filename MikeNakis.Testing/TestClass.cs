namespace MikeNakis.Testing;

using System.Collections.Generic;
using System.Linq;
using MikeNakis.Kit;
using MikeNakis.Kit.Collections;
using MikeNakis.Kit.Extensions;
using MikeNakis.Kit.Logging;
using static MikeNakis.Kit.GlobalStatics;
using Math = System.Math;
using Sys = System;
using SysCompiler = System.Runtime.CompilerServices;
using SysDiag = System.Diagnostics;
using VSTesting = Microsoft.VisualStudio.TestTools.UnitTesting;

///<summary>Base class for all test classes.</summary>
public abstract class TestClass
{
	///<summary>Static Constructor</summary>
	static TestClass()
	{
		if( !DebugMode )
			throw Failure();
	}

	static AuditFile? auditFile;

	public static TextConsumer GetAuditTextConsumer( [SysCompiler.CallerFilePath] string? callerFilePathName = null, [SysCompiler.CallerMemberName] string? callerMemberName = null, string? partName = null )
	{
		Assert( callerFilePathName != null );
		Assert( callerMemberName != null );
		auditFile ??= AuditFile.Create( callerFilePathName );
		string sectionName = getSectionName( callerMemberName, partName );
		auditFile.SetSectionName( sectionName );
		return auditFile.TextConsumer;

		static string getSectionName( string callerMemberName, string? partName )
		{
			if( partName == null )
				return callerMemberName;
			return callerMemberName + " " + partName;
		}
	}

	public static void FlushAudit() => auditFile.OrThrow().Flush();

	// PEARL: if the TestContext parameter is not specified, Visual Studio will not run the tests and will not give the
	// slightest clue as to why it did not run them.
	[VSTesting.ClassInitialize]
	public static void OnTestClassInitialize( VSTesting.TestContext _ )
	{
		Assert( auditFile == null );
	}

	[VSTesting.ClassCleanup]
	public static void OnTestClassCleanup()
	{
		if( auditFile != null )
		{
			auditFile.Dispose();
			auditFile = null;
		}
	}

	[VSTesting.TestCleanup]
	public static void OnTestMethodCleanup()
	{
		auditFile?.Flush();
	}

	protected static Sys.Exception? TryCatch( Sys.Action procedure )
	{
		Assert( !KitHelpers.FailureTesting.Value );
		KitHelpers.FailureTesting.Value = true;
		try
		{
			procedure.Invoke();
			return null;
		}
		catch( Sys.Exception exception )
		{
			return exception;
		}
		finally
		{
			KitHelpers.FailureTesting.Value = false;
		}
	}

	protected static void AssertTextsEqual( string expectedText, string actualText ) => AssertTextsEqual( "expected", expectedText, "actual", actualText );

	protected static void AssertTextsEqual( string leftTitle, string leftText, string rightTitle, string rightText )
	{
		if( leftText == rightText )
			return;
		LogTextDifferences( leftTitle, leftText, rightTitle, rightText );
		Assert( false );
	}

	// TODO: improve this! See https://stackoverflow.com/a/27151562/773113
	public static void LogTextDifferences( string leftTitle, string leftText, string rightTitle, string rightText )
	{
		IReadOnlyList<string> leftLines = split( leftText );
		IReadOnlyList<string> rightLines = split( rightText );
		int width = leftLines.Max( s => s.Length );
		if( width < leftTitle.Length )
			width = leftTitle.Length;
		width += 4;
		int maxCount = Math.Max( leftLines.Count, rightLines.Count );
		Log.Debug( leftTitle.PadRight( width ) + rightTitle );
		for( int i = 0; i < maxCount; i++ )
		{
			string leftLine = getStringOrEmpty( leftLines, i );
			string rightLine = getStringOrEmpty( rightLines, i );
			LogLevel logLevel = leftLine == rightLine ? LogLevel.Info : LogLevel.Warn;
			Log.MessageWithGivenLevel( logLevel, leftLine.PadRight( width ) + rightLine );
		}
		return;

		static string getStringOrEmpty( IReadOnlyList<string> array, int index ) => index < array.Count ? array[index] : "";

		static IReadOnlyList<string> split( string s ) //
			=> s.Split( "\n" ) //
					.Select( s => s.Replace2( "\t", " \u2500\u2192 " ) )
					.Select( s => s.Replace2( "\r", "\u21B5" ) )
					//.Select( s => s.Replace( "\n", "\u2193" ) )
					//.Select( KitHelpers.EscapeForCSharp ) //
					.Select( s => "\"" + s + "\"" );
	}

	public static void Benchmark( int count, string text, Sys.Action procedure, [SysCompiler.CallerFilePath] string callerFilePath = "", [SysCompiler.CallerLineNumber] int callerLineNumber = 0 )
	{
		Sys.TimeSpan bestDuration = Sys.TimeSpan.MaxValue;
		for( int i = 0; i < count; i++ )
		{
			Sys.TimeSpan duration = time( procedure );
			bestDuration = duration < bestDuration ? duration : bestDuration;
		}
		Log.Info( $"{text}: {bestDuration.TotalMilliseconds:F1} ms", callerFilePath, callerLineNumber );
		return;

		static Sys.TimeSpan time( Sys.Action procedure )
		{
			SysDiag.Stopwatch sw = SysDiag.Stopwatch.StartNew();
			long start = sw.ElapsedMilliseconds;
			procedure.Invoke();
			long end = sw.ElapsedMilliseconds;
			return Sys.TimeSpan.FromMilliseconds( end - start );
		}
	}
}
