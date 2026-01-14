			if (fields[i] == _('Online Users')) {
				ctstatus.appendChild(E('tr', { 'class': 'tr' }, [
					E('td', { 'class': 'td left', 'width': '33%' }, [ fields[i] ]),
					E('td', { 'class': 'td left' }, [
						(fields[i + 1] != null) ? fields[i + 1] : '?'
					])
				]));
			} else {
				ctstatus.appendChild(E('tr', { 'class': 'tr' }, [
					E('td', { 'class': 'td left', 'width': '33%' }, [ fields[i] ]),
					E('td', { 'class': 'td left' }, [
						(fields[i + 1] != null) ? progressbar(fields[i + 1], ct_max) : '?'
					])
				]));
			}