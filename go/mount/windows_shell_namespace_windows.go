//go:build windows

// Windows shell namespace helpers surface the sync root inside "This PC".
package mount

import (
	"fmt"
	"path/filepath"
	"strings"

	"github.com/google/uuid"
	"golang.org/x/sys/windows"
	"golang.org/x/sys/windows/registry"
)

const (
	thisPCNamespaceBase   = `Software\Microsoft\Windows\CurrentVersion\Explorer\MyComputer\NameSpace`
	classesCLSIDBase      = `Software\Classes\CLSID`
	folderShortcutCLSID   = `{0E5AAE11-A475-4c5b-AB00-C66DE400274E}`
	thisPCSortOrderIndex  = 0x42
	shellFolderAttributes = 0xF080004D
)

var shChangeNotifyProc = windows.NewLazySystemDLL("shell32.dll").NewProc("SHChangeNotify")

type windowsShellNamespace struct {
	clsid string
	name  string
	path  string
}

type windowsShellNamespaceEntry struct {
	clsid string
	name  string
}

func newWindowsShellNamespace(bucket, mountPath string) *windowsShellNamespace {
	namespaceID := uuid.NewSHA1(
		uuid.NameSpaceURL,
		[]byte("cloud-volume:this-pc:"+strings.ToLower(strings.TrimSpace(bucket))+":"+filepath.Clean(mountPath)),
	)
	return &windowsShellNamespace{
		clsid: "{" + strings.ToUpper(namespaceID.String()) + "}",
		name:  "云卷 - " + strings.TrimSpace(bucket),
		path:  filepath.Clean(mountPath),
	}
}

func (n *windowsShellNamespace) Register() error {
	if strings.TrimSpace(n.path) == "" {
		return fmt.Errorf("This PC namespace path is required")
	}
	if err := n.registerClass(); err != nil {
		return err
	}
	if err := n.registerNameSpace(); err != nil {
		_ = n.Unregister()
		return err
	}
	notifyExplorerShellChanged()
	return nil
}

func (n *windowsShellNamespace) Unregister() error {
	var firstErr error
	if err := registry.DeleteKey(registry.CURRENT_USER, filepath.Join(thisPCNamespaceBase, n.clsid)); err != nil && err != registry.ErrNotExist {
		firstErr = fmt.Errorf("remove This PC namespace key: %w", err)
	}
	if err := deleteRegistryTree(registry.CURRENT_USER, filepath.Join(classesCLSIDBase, n.clsid)); err != nil && firstErr == nil {
		firstErr = err
	}
	notifyExplorerShellChanged()
	return firstErr
}

func (n *windowsShellNamespace) registerClass() error {
	rootPath := filepath.Join(classesCLSIDBase, n.clsid)
	rootKey, _, err := registry.CreateKey(registry.CURRENT_USER, rootPath, registry.ALL_ACCESS)
	if err != nil {
		return fmt.Errorf("create CLSID key: %w", err)
	}
	defer rootKey.Close()
	if err := rootKey.SetStringValue("", n.name); err != nil {
		return fmt.Errorf("set CLSID display name: %w", err)
	}
	if err := rootKey.SetDWordValue("System.IsPinnedToNameSpaceTree", 1); err != nil {
		return fmt.Errorf("pin namespace tree: %w", err)
	}
	if err := rootKey.SetDWordValue("SortOrderIndex", thisPCSortOrderIndex); err != nil {
		return fmt.Errorf("set sort order: %w", err)
	}

	inprocKey, _, err := registry.CreateKey(registry.CURRENT_USER, filepath.Join(rootPath, `InProcServer32`), registry.ALL_ACCESS)
	if err != nil {
		return fmt.Errorf("create InProcServer32 key: %w", err)
	}
	defer inprocKey.Close()
	if err := inprocKey.SetStringValue("", `%SystemRoot%\System32\shell32.dll`); err != nil {
		return fmt.Errorf("set shell handler dll: %w", err)
	}
	if err := inprocKey.SetStringValue("ThreadingModel", "Both"); err != nil {
		return fmt.Errorf("set threading model: %w", err)
	}

	instanceKey, _, err := registry.CreateKey(registry.CURRENT_USER, filepath.Join(rootPath, `Instance`), registry.ALL_ACCESS)
	if err != nil {
		return fmt.Errorf("create Instance key: %w", err)
	}
	defer instanceKey.Close()
	if err := instanceKey.SetStringValue("CLSID", folderShortcutCLSID); err != nil {
		return fmt.Errorf("set folder shortcut CLSID: %w", err)
	}

	propertyBagKey, _, err := registry.CreateKey(registry.CURRENT_USER, filepath.Join(rootPath, `Instance\InitPropertyBag`), registry.ALL_ACCESS)
	if err != nil {
		return fmt.Errorf("create InitPropertyBag key: %w", err)
	}
	defer propertyBagKey.Close()
	if err := propertyBagKey.SetStringValue("TargetFolderPath", n.path); err != nil {
		return fmt.Errorf("set target folder path: %w", err)
	}
	if err := propertyBagKey.SetDWordValue("Attributes", 0x11); err != nil {
		return fmt.Errorf("set property bag attributes: %w", err)
	}

	shellFolderKey, _, err := registry.CreateKey(registry.CURRENT_USER, filepath.Join(rootPath, `ShellFolder`), registry.ALL_ACCESS)
	if err != nil {
		return fmt.Errorf("create ShellFolder key: %w", err)
	}
	defer shellFolderKey.Close()
	if err := shellFolderKey.SetDWordValue("Attributes", shellFolderAttributes); err != nil {
		return fmt.Errorf("set shell folder attributes: %w", err)
	}

	return nil
}

func (n *windowsShellNamespace) registerNameSpace() error {
	nameSpaceKey, _, err := registry.CreateKey(
		registry.CURRENT_USER,
		filepath.Join(thisPCNamespaceBase, n.clsid),
		registry.ALL_ACCESS,
	)
	if err != nil {
		return fmt.Errorf("create This PC namespace key: %w", err)
	}
	defer nameSpaceKey.Close()
	if err := nameSpaceKey.SetStringValue("", n.name); err != nil {
		return fmt.Errorf("set This PC namespace name: %w", err)
	}
	return nil
}

func cleanupLegacyWindowsShellNamespaces() error {
	entries, err := listWindowsShellNamespaces()
	if err != nil {
		return err
	}
	var firstErr error
	for _, entry := range entries {
		if !isManagedWindowsShellNamespace(entry.name) {
			continue
		}
		if err := registry.DeleteKey(registry.CURRENT_USER, filepath.Join(thisPCNamespaceBase, entry.clsid)); err != nil && err != registry.ErrNotExist && firstErr == nil {
			firstErr = fmt.Errorf("remove legacy This PC namespace key: %w", err)
		}
		if err := deleteRegistryTree(registry.CURRENT_USER, filepath.Join(classesCLSIDBase, entry.clsid)); err != nil && firstErr == nil {
			firstErr = err
		}
	}
	notifyExplorerShellChanged()
	return firstErr
}

func listWindowsShellNamespaces() ([]windowsShellNamespaceEntry, error) {
	rootKey, err := registry.OpenKey(registry.CURRENT_USER, thisPCNamespaceBase, registry.ENUMERATE_SUB_KEYS)
	if err != nil {
		if err == registry.ErrNotExist {
			return nil, nil
		}
		return nil, fmt.Errorf("open This PC namespace root: %w", err)
	}
	defer rootKey.Close()

	names, err := rootKey.ReadSubKeyNames(-1)
	if err != nil {
		return nil, fmt.Errorf("list This PC namespace keys: %w", err)
	}
	entries := make([]windowsShellNamespaceEntry, 0, len(names))
	for _, name := range names {
		itemKey, openErr := registry.OpenKey(registry.CURRENT_USER, filepath.Join(thisPCNamespaceBase, name), registry.QUERY_VALUE)
		if openErr != nil {
			continue
		}
		displayName, _, _ := itemKey.GetStringValue("")
		_ = itemKey.Close()
		entries = append(entries, windowsShellNamespaceEntry{
			clsid: name,
			name:  displayName,
		})
	}
	return entries, nil
}

func isManagedWindowsShellNamespace(name string) bool {
	trimmed := strings.TrimSpace(name)
	return strings.HasPrefix(trimmed, "云卷 - ") || strings.HasPrefix(trimmed, "Cloud Volume ")
}

func deleteRegistryTree(root registry.Key, path string) error {
	subKey, err := registry.OpenKey(root, path, registry.ENUMERATE_SUB_KEYS|registry.QUERY_VALUE|registry.SET_VALUE)
	if err != nil {
		if err == registry.ErrNotExist {
			return nil
		}
		return fmt.Errorf("open registry tree %q: %w", path, err)
	}
	defer subKey.Close()

	children, err := subKey.ReadSubKeyNames(-1)
	if err != nil {
		return fmt.Errorf("list registry children for %q: %w", path, err)
	}
	for _, child := range children {
		if err := deleteRegistryTree(root, filepath.Join(path, child)); err != nil {
			return err
		}
	}
	if err := registry.DeleteKey(root, path); err != nil && err != registry.ErrNotExist {
		return fmt.Errorf("delete registry key %q: %w", path, err)
	}
	return nil
}

func notifyExplorerShellChanged() {
	const (
		shcneAssocChanged = 0x08000000
		shcnfIDList       = 0x0000
		shcnfFlush        = 0x1000
	)
	_, _, _ = shChangeNotifyProc.Call(
		uintptr(shcneAssocChanged),
		uintptr(shcnfIDList|shcnfFlush),
		0,
		0,
	)
}
