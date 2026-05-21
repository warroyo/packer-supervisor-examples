package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"net/url"
	"os"
	"strings"
	"time"

	"github.com/vmware/govmomi"
	"github.com/vmware/govmomi/find"
	"github.com/vmware/govmomi/object"
	"github.com/vmware/govmomi/vim25/methods"
	"github.com/vmware/govmomi/vim25/types"
	"golang.org/x/mobile/event/key"
)

type Config struct {
	VMName      string   `json:"vm_name"`
	BootCommand []string `json:"boot_command"`
}

// UsbModifier tracks if the character requires a Shift key (e.g., ':' or '_')
type UsbModifier struct {
	Code  key.Code
	Shift bool
}

// Map ASCII characters to the official Golang USB HID Code constants
var keyMap = map[rune]UsbModifier{
	'a': {key.CodeA, false}, 'b': {key.CodeB, false}, 'c': {key.CodeC, false},
	'd': {key.CodeD, false}, 'e': {key.CodeE, false}, 'f': {key.CodeF, false},
	'g': {key.CodeG, false}, 'h': {key.CodeH, false}, 'i': {key.CodeI, false},
	'j': {key.CodeJ, false}, 'k': {key.CodeK, false}, 'l': {key.CodeL, false},
	'm': {key.CodeM, false}, 'n': {key.CodeN, false}, 'o': {key.CodeO, false},
	'p': {key.CodeP, false}, 'q': {key.CodeQ, false}, 'r': {key.CodeR, false},
	's': {key.CodeS, false}, 't': {key.CodeT, false}, 'u': {key.CodeU, false},
	'v': {key.CodeV, false}, 'w': {key.CodeW, false}, 'x': {key.CodeX, false},
	'y': {key.CodeY, false}, 'z': {key.CodeZ, false},
	'1': {key.Code1, false}, '2': {key.Code2, false}, '3': {key.Code3, false},
	'4': {key.Code4, false}, '5': {key.Code5, false}, '6': {key.Code6, false},
	'7': {key.Code7, false}, '8': {key.Code8, false}, '9': {key.Code9, false},
	'0': {key.Code0, false},
	' ': {key.CodeSpacebar, false},
	'-': {key.CodeHyphenMinus, false},
	'=': {key.CodeEqualSign, false},
	'.': {key.CodeFullStop, false},
	'/': {key.CodeSlash, false},
	// Shift-required mappings
	':': {key.CodeSemicolon, true},   // Shift + ; = :
	'_': {key.CodeHyphenMinus, true}, // Shift + - = _
}

// Map special Packer-style tags to their physical keyboard events
var specialKeys = map[string]key.Code{
	"<enter>": key.CodeReturnEnter,
	"<tab>":   key.CodeTab,
	"<bs>":    key.CodeDeleteBackspace,
}

func main() {
	var configFile string
	var vmFlag string

	flag.StringVar(&configFile, "config", "", "Path to JSON config file with boot_command")
	flag.StringVar(&vmFlag, "vm", "", "VM name (overrides config file)")
	flag.Parse()

	vcURL := os.Getenv("GOVMOMI_URL")
	if vcURL == "" {
		log.Fatal("Please set GOVMOMI_URL environment variable")
	}

	cfg := Config{
		VMName: "manual-iso-kickstart-test",
	}

	if configFile != "" {
		data, err := os.ReadFile(configFile)
		if err != nil {
			log.Fatalf("Error reading config file: %v", err)
		}
		if err := json.Unmarshal(data, &cfg); err != nil {
			log.Fatalf("Error parsing config file: %v", err)
		}
	}

	if vmFlag != "" {
		cfg.VMName = vmFlag
	}

	if len(cfg.BootCommand) == 0 {
		log.Fatal("No boot_command defined. Use --config with a JSON file.")
	}

	bootCommand := strings.Join(cfg.BootCommand, "")

	u, err := url.Parse(vcURL)
	if err != nil {
		log.Fatalf("Error parsing URL: %v", err)
	}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	client, err := govmomi.NewClient(ctx, u, true)
	if err != nil {
		log.Fatalf("Error connecting to vCenter: %v", err)
	}

	finder := find.NewFinder(client.Client, true)

	dc, err := finder.DefaultDatacenter(ctx)
	if err != nil {
		log.Fatalf("Error finding default datacenter: %v", err)
	}
	finder.SetDatacenter(dc)

	vm, err := finder.VirtualMachine(ctx, cfg.VMName)
	if err != nil {
		log.Fatalf("Error finding VM %s: %v", cfg.VMName, err)
	}

	fmt.Printf("Sending native USB scan codes to %s...\n", cfg.VMName)
	if err = sendBootCommand(ctx, client, vm, bootCommand); err != nil {
		log.Fatalf("Error sending boot command: %v", err)
	}
	fmt.Println("Boot command sent successfully!")
}

// sendBootCommand parses the string and sends the keystrokes
func sendBootCommand(ctx context.Context, client *govmomi.Client, vm *object.VirtualMachine, cmd string) error {
	i := 0
	for i < len(cmd) {
		// Handle <tags>
		if cmd[i] == '<' {
			end := strings.Index(cmd[i:], ">")
			if end != -1 {
				tag := cmd[i : i+end+1]
				
				if strings.HasPrefix(tag, "<wait") {
					durationStr := strings.TrimSuffix(strings.TrimPrefix(tag, "<wait"), ">")
					if durationStr == "" {
						time.Sleep(1 * time.Second)
					} else {
						d, _ := time.ParseDuration(durationStr)
						time.Sleep(d)
					}
				} else if keyCode, ok := specialKeys[tag]; ok {
					err := TypeOnKeyboard(ctx, client, vm, keyCode, false)
					if err != nil {
						return err
					}
				}
				i += end + 1
				continue
			}
		}

		// Handle normal string characters
		char := rune(cmd[i])
		if modifier, ok := keyMap[char]; ok {
			err := TypeOnKeyboard(ctx, client, vm, modifier.Code, modifier.Shift)
			if err != nil {
				return err
			}
		} else {
			fmt.Printf("Warning: Character '%c' not mapped, skipping.\n", char)
		}
		
		time.Sleep(50 * time.Millisecond)
		i++
	}
	return nil
}

// TypeOnKeyboard exactly mirrors the Packer plugin's approach (Line 23 of vm_keyboard.go)
func TypeOnKeyboard(ctx context.Context, client *govmomi.Client, vm *object.VirtualMachine, scancode key.Code, shift bool) error {
	var spec types.UsbScanCodeSpec

	// The default modifiers (false)
	var ctrl, alt bool

	// Add the exact Bitwise formatting Packer uses: (scancode << 16 | 7)
	spec.KeyEvents = append(spec.KeyEvents, types.UsbScanCodeSpecKeyEvent{
		UsbHidCode: int32(scancode)<<16 | 7,
		Modifiers: &types.UsbScanCodeSpecModifierType{
			LeftControl: &ctrl,
			LeftAlt:     &alt,
			LeftShift:   &shift,
		},
	})

	req := &types.PutUsbScanCodes{
		This: vm.Reference(),
		Spec: spec,
	}

	// Call the vCenter API natively
	_, err := methods.PutUsbScanCodes(ctx, client.RoundTripper, req)
	return err
}