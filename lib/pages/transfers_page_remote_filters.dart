part of 'transfers_page.dart';

// Queue filters are isolated from the list layout to keep each page part small.
extension _TransfersPageRemoteFilters on _TransfersPageState {
  Widget _buildRemoteFilters() {
    return Row(
      children: [
        Expanded(
          child: ShadInput(
            controller: _searchController,
            placeholder: const Text('搜索操作、路径、存储桶或账号'),
          ),
        ),
        const SizedBox(width: 12),
        _remoteDropdown<_RemoteTaskStatusFilter>(
          value: _remoteStatusFilter,
          items: _RemoteTaskStatusFilter.values,
          labelBuilder: (value) => value.label,
          onChanged: (value) {
            if (value != null) {
              _remoteSetState(() => _remoteStatusFilter = value);
            }
          },
        ),
        const SizedBox(width: 12),
        _remoteDropdown<_RemoteTaskKindFilter>(
          value: _remoteKindFilter,
          items: _RemoteTaskKindFilter.values,
          labelBuilder: (value) => value.label,
          onChanged: (value) {
            if (value != null) {
              _remoteSetState(() => _remoteKindFilter = value);
            }
          },
        ),
      ],
    );
  }
}
