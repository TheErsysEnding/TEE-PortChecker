// =============================================================================
//  TEE PortChecker - Starter
// =============================================================================
//  Diese winzige Anwendung tut genau eine Sache: sie startet
//  src\PortCheck.Gui.ps1 mit den richtigen Schaltern und beendet sich wieder.
//
//  WARUM UEBERHAUPT EINE .EXE?
//    Nur wegen des Symbols und des Doppelklicks. Eine .bat-Datei zeigt in
//    Windows immer dasselbe Zahnrad-Symbol und laesst kurz ein schwarzes
//    Fenster aufblitzen.
//
//  WAS SIE AUSDRUECKLICH NICHT TUT:
//    Sie enthaelt keinen Programmcode des Werkzeugs. Der liegt weiterhin
//    vollstaendig lesbar im Ordner "src" daneben. Das ist Absicht: bei einem
//    Programm, das Netzwerkverbindungen oeffnet, ist nachlesbarer Quelltext
//    mehr wert als eine kompilierte Datei, der man vertrauen muss. Wer der
//    .exe nicht traut, startet einfach TEE-PortChecker.bat - das Ergebnis ist
//    dasselbe.
//
//  Uebersetzt wird mit tools\Build-Exe.ps1 (nutzt den C#-Compiler, der auf
//  jedem Windows ohnehin vorhanden ist).
//
//  Lizenz: MIT (siehe LICENSE)
// =============================================================================

using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Text;
using System.Windows.Forms;

internal static class Program
{
    private const string ScriptRelativePath = @"src\PortCheck.Gui.ps1";
    private const string AppName = "TEE PortChecker";

    [STAThread]
    private static int Main(string[] args)
    {
        string exePath = Assembly.GetExecutingAssembly().Location;
        string baseDir = Path.GetDirectoryName(exePath);
        if (string.IsNullOrEmpty(baseDir))
        {
            baseDir = Environment.CurrentDirectory;
        }

        string scriptPath = Path.Combine(baseDir, ScriptRelativePath);

        if (!File.Exists(scriptPath))
        {
            MessageBox.Show(
                "Die Programmdateien wurden nicht gefunden.\n\n" +
                "Erwartet wurde:\n" + scriptPath + "\n\n" +
                "Diese Datei ist nur ein Starter - der eigentliche Programmcode liegt im " +
                "Ordner \"src\" daneben. Bitte das heruntergeladene Archiv vollstaendig " +
                "entpacken und die .exe im entpackten Ordner starten, nicht einzeln " +
                "herauskopieren.",
                AppName, MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }

        // -NoProfile  : Profilskripte des Anwenders bleiben aussen vor
        // -STA        : von WPF und der Zwischenablage zwingend gefordert
        // -WindowStyle Hidden : kein schwarzes Fenster im Hintergrund
        // -ExecutionPolicy Bypass : gilt nur fuer diesen einen Start und
        //               aendert nichts an den Einstellungen des Rechners
        StringBuilder arguments = new StringBuilder();
        arguments.Append("-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File \"");
        arguments.Append(scriptPath);
        arguments.Append("\"");

        // Aufrufparameter durchreichen, damit z. B. -Theme crimson auch
        // ueber die .exe funktioniert.
        foreach (string argument in args)
        {
            arguments.Append(' ');
            if (argument.IndexOf(' ') >= 0)
            {
                arguments.Append('"').Append(argument).Append('"');
            }
            else
            {
                arguments.Append(argument);
            }
        }

        ProcessStartInfo startInfo = new ProcessStartInfo("powershell.exe", arguments.ToString());
        startInfo.UseShellExecute = false;
        startInfo.CreateNoWindow = true;
        startInfo.WorkingDirectory = baseDir;

        try
        {
            Process.Start(startInfo);
        }
        catch (Exception ex)
        {
            MessageBox.Show(
                "Windows PowerShell liess sich nicht starten.\n\n" + ex.Message +
                "\n\nWindows PowerShell 5.1 gehoert zum Lieferumfang von Windows 10 und 11. " +
                "Fehlt es, hilft nur das Nachinstallieren ueber die Windows-Features.",
                AppName, MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 2;
        }

        // Der Starter wird nicht mehr gebraucht und beendet sich sofort -
        // er soll keinen Prozess im Speicher halten.
        return 0;
    }
}
