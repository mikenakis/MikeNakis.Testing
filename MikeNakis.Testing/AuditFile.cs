namespace MikeNakis.Testing;

using MikeNakis.Kit;
using MikeNakis.Kit.FileSystem;
using static MikeNakis.Kit.GlobalStatics;
using Git = LibGit2Sharp;
using Sys = System;
using SysDiag = System.Diagnostics;
using SysText = System.Text;

sealed class AuditFile : Sys.IDisposable
{
	const string auditFileExtension = ".audit";

	public static AuditFile Create( string callerFilePathName )
	{
		FilePath callerFilePath = FilePath.FromAbsolutePath( callerFilePathName );
		FilePath auditFilePath = callerFilePath.WithReplacedExtension( auditFileExtension );
		bool isResetToCommittedVersion = auditFilePath.Exists() && tryResetFile( auditFilePath );
		return new AuditFile( auditFilePath, isResetToCommittedVersion );

		// [Claude] Returns whether the file was reset to its committed version; an ignored or untracked file is left as it
		// is.
		static bool tryResetFile( FilePath filePath )
		{
			DirectoryPath gitDirectoryPath = getGitDirectoryPath( filePath.Directory );
			using( Git.Repository repository = new( gitDirectoryPath.Path ) )
			{
				Git.FileStatus fileStatus = repository.RetrieveStatus( filePath.Path );
				if( fileStatus.HasFlag( Git.FileStatus.Ignored ) )
					return false;
				if( fileStatus.HasFlag( Git.FileStatus.NewInWorkdir ) )
					return false;

				// PEARL: Git checkout sometimes fails when the modified file is only different by line endings.
				//        see https://stackoverflow.com/q/2016404/773113
				//        To work around this problem, we delete the file prior to checking it out.
				filePath.Delete();
				Git.CheckoutOptions checkoutOptions = new() { CheckoutModifiers = Git.CheckoutModifiers.Force };
				string committishOrBranchSpec = True ? repository.Head.FriendlyName : "HEAD";
				repository.CheckoutPaths( committishOrBranchSpec, EnumerableOf( filePath.Path ), checkoutOptions );
				return true;
			}

			static DirectoryPath getGitDirectoryPath( DirectoryPath directoryPath )
			{
				while( !directoryPath.Directory( ".git" ).Exists() )
					directoryPath = directoryPath.GetParent() ?? throw new AssertionFailureException();
				return directoryPath;
			}
		}
	}

	readonly LifeGuard lifeGuard = LifeGuard.Create();
	readonly FilePath outputFilePath;
	readonly SysText.StringBuilder stringBuilder = new();
	public bool Break { get; } = true;
	string currentSectionName = "";
	readonly string? oldContent;
	readonly bool isResetToCommittedVersion;
	public TextConsumer TextConsumer { get; }

	public AuditFile( FilePath outputFilePath, bool isResetToCommittedVersion )
	{
		this.outputFilePath = outputFilePath;
		this.isResetToCommittedVersion = isResetToCommittedVersion;
		if( outputFilePath.Exists() )
			oldContent = outputFilePath.ReadAllText();
		else
		{
			Log.Warn( $"Audit file is being added: {outputFilePath.Path}" );
			//if( Break )
			//	SysDiag.Debugger.Break(); //audit file added!
		}
		TextConsumer = new StringBuilderTextConsumer( stringBuilder );
	}

	void appendSingleDividerLine() => stringBuilder.Append( new string( '-', 80 ) ).Append( '\n' );

	public void Flush()
	{
		Assert( lifeGuard.IsAliveAssertion() );
		string newContent = stringBuilder.ToString();
		outputFilePath.WriteAllText( newContent );
	}

	public void Dispose()
	{
		Assert( lifeGuard.IsAliveAssertion() );
		Flush();
		string newContent = stringBuilder.ToString();
		if( oldContent != newContent )
		{
			string verb = oldContent == null ? "added" : "changed";
			string baseline = isResetToCommittedVersion ? "compared with the committed version" : "compared with the version on disk, which is not committed";
			Log.Warn( $"Audit file {verb}! ({baseline})" );
			Log.Warn( $"This is the {verb} audit file.", outputFilePath.Path, 0 );
			if( !SysDiag.Debugger.IsAttached )
				throw Failure();
			//if( Break )
			//	SysDiag.Debugger.Break(); //audit file added or changed!
		}
		lifeGuard.Dispose();
	}

	public void SetSectionName( string sectionName )
	{
		if( sectionName == currentSectionName )
			return;
		currentSectionName = sectionName;
		if( stringBuilder.Length > 0 )
		{
			if( stringBuilder.Length < 2 || !(stringBuilder[^1] == '\n' && stringBuilder[^2] == '\n') )
				stringBuilder.Append( '\n' );
		}
		appendSingleDividerLine();
		stringBuilder.Append( sectionName ).Append( '\n' );
		appendSingleDividerLine();
		stringBuilder.Append( '\n' );
	}
}
