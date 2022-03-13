import 'dart:io';
import 'package:github/github.dart';
import 'package:yaml/yaml.dart';

const semvers = ['major', 'minor', 'patch'];

/// Meant to be run from the github workflow.
/// Expected arguments of:
/// [repo] the full repo owner/name format
/// [pr number] PR number of which to release
/// the semver label is expected to be on the PR
void main(List<String> args) async {
  if (args.length < 2) {
    print('Usage: dart tool/auto_release_on_merge owner_and_repo pull_number');
    exit(0);
  }
  final fullrepo = args[0];
  final pullnumber = int.parse(args[1]);
  final currentVersion = getVersion();
  var slug = RepositorySlug.full(fullrepo);

  print('Loading PR $pullnumber from $slug');
  var gh = GitHub(auth: findAuthenticationFromEnvironment());
  print('TOKEN: ${gh.auth?.token}');
  var pr = await gh.pullRequests.get(slug, pullnumber);
  if (!(pr.merged ?? false)) {
    print('PR not merged');
    exit(1);
  }
  print('PR loaded');

  var labels = pr.labels ?? [];
  var semverLabel = labels
      .map((e) => e.name)
      .firstWhere((label) => label.startsWith('semver'), orElse: () => '');
  if (semverLabel.isEmpty) {
    print('No semver label found');
    exit(2);
  }
  semverLabel = semverLabel.replaceAll('semver:', '');
  // ensure the semver label is valid
  if (!semvers.contains(semverLabel)) {
    print('semver label is not one of $semvers');
    exit(3);
  }
  print('Semver label: $semverLabel');
  Process.runSync('cider', ['bump', semverLabel]);
  var newVersion = getVersion();
  print('Current Version: $currentVersion');
  print('New Version    : $newVersion');

  var rn = await gh.repositories.generateReleaseNotes(CreateReleaseNotes(
      slug.owner, slug.name, newVersion,
      previousTagName: currentVersion));

  var releaseNotes = rn.body.replaceFirst('## What\'s Changed','');
  releaseNotes = '## $newVersion\n$releaseNotes';
  
  print(releaseNotes);

  var log = File('CHANGELOG.md');
  var logdata = log.readAsStringSync();
  log.writeAsStringSync('${releaseNotes}\n\n$logdata');
  
  // Process.runSync('git', ['add', 'pubspec.yaml', 'CHANGELOG.md']);
  // Process.runSync('git', ['commit', '-m', 'auto prep $newVersion']);
  // Process.runSync('git', ['push']);
  var res = Process.runSync('git', ['rev-parse', 'HEAD']);
  var commit = res.stdout;
  print('autoprep commit: $commit');

  // var release = await gh.repositories.createRelease(
  //     slug,
  //     CreateRelease.from(
  //         tagName: newVersion,
  //         name: newVersion,
  //         generateReleaseNotes: true,
  //         targetCommitish: commit,
  //         isDraft: false,
  //         isPrerelease: false));

  // print('$newVersion release created at ${release.createdAt}');
  
  exit(0);
}

String getVersion() {
  var y = loadYaml(File('pubspec.yaml').readAsStringSync());
  var newVersion = y['version'].toString();
  return newVersion;
}
